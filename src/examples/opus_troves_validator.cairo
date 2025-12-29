use opus::types::AssetBalance;
use starknet::ContractAddress;
use wadray::Wad;

#[starknet::interface]
pub trait IAbbot<TContractState> {
    // getters
    fn get_trove_owner(self: @TContractState, trove_id: u64) -> Option<ContractAddress>;
    fn get_user_trove_ids(self: @TContractState, user: ContractAddress) -> Span<u64>;
    fn get_troves_count(self: @TContractState) -> u64;
    fn get_trove_asset_balance(self: @TContractState, trove_id: u64, yang: ContractAddress) -> u128;
    // external
    fn open_trove(
        ref self: TContractState,
        yang_assets: Span<AssetBalance>,
        forge_amount: Wad,
        max_forge_fee_pct: Wad,
    ) -> u64;
    fn close_trove(ref self: TContractState, trove_id: u64);
    fn deposit(ref self: TContractState, trove_id: u64, yang_asset: AssetBalance);
    fn withdraw(ref self: TContractState, trove_id: u64, yang_asset: AssetBalance);
    fn forge(ref self: TContractState, trove_id: u64, amount: Wad, max_forge_fee_pct: Wad);
    fn melt(ref self: TContractState, trove_id: u64, amount: Wad);
}

#[starknet::interface]
pub trait IEntryValidatorMock<TState> {
    fn get_trove_asset(self: @TState, tournament_id: u64) -> ContractAddress;
    fn get_trove_threshold(self: @TState, tournament_id: u64) -> u128;
    fn get_value_per_entry(self: @TState, tournament_id: u64) -> u128;
    fn get_max_entries(self: @TState, tournament_id: u64) -> u8;
}

#[starknet::contract]
pub mod OpusTrovesValidator {
    use budokan_entry_requirement::entry_validator::EntryValidatorComponent;
    use budokan_entry_requirement::entry_validator::EntryValidatorComponent::EntryValidator;
    use core::num::traits::Zero;
    use openzeppelin_introspection::src5::SRC5Component;
    use opus::periphery::interfaces::{
        IFrontendDataProviderDispatcher, IFrontendDataProviderDispatcherTrait,
    };
    use opus::periphery::types::TroveInfo;
    use starknet::ContractAddress;
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};
    use wadray::Wad;
    use super::{IAbbotDispatcher, IAbbotDispatcherTrait};

    // Opus mainnet addresses - use try_into for const addresses
    fn abbot_address() -> ContractAddress {
        0x04d0bb0a4c40012384e7c419e6eb3c637b28e8363fb66958b60d90505b9c072f.try_into().unwrap()
    }

    fn fdp_address() -> ContractAddress {
        0x023037703b187f6ff23b883624a0a9f266c9d44671e762048c70100c2f128ab9.try_into().unwrap()
    }

    component!(path: EntryValidatorComponent, storage: entry_validator, event: EntryValidatorEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    #[abi(embed_v0)]
    impl EntryValidatorImpl =
        EntryValidatorComponent::EntryValidatorImpl<ContractState>;
    impl EntryValidatorInternalImpl = EntryValidatorComponent::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        entry_validator: EntryValidatorComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        tournament_trove_asset: Map<u64, ContractAddress>,
        tournament_trove_threshold: Map<u64, u128>,
        tournament_entry_limit: Map<u64, u8>,
        tournament_entries_per_address: Map<(u64, ContractAddress), u8>,
        tournament_value_per_entry: Map<u64, u128>, // Value required per entry (0 = fixed limit)
        tournament_max_entries: Map<u64, u8> // Maximum entries cap (0 = no cap)
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        EntryValidatorEvent: EntryValidatorComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
    }

    #[constructor]
    fn constructor(ref self: ContractState, budokan_address: ContractAddress) {
        // Trove collateral can change, so registration_only = false (allow banning)
        self.entry_validator.initializer(budokan_address, false);
    }

    // Implement the EntryValidator trait for the contract
    impl EntryValidatorImplInternal of EntryValidator<ContractState> {
        fn validate_entry(
            self: @ContractState,
            tournament_id: u64,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) -> bool {
            assert!(qualification.len() == 0, "Opus Entry Validator: Qualification data invalid");

            // Must meet trove requirements AND have entries available
            self.check_trove_requirements(tournament_id, player_address)
                && self.has_entries_available(tournament_id, player_address)
        }

        /// Check if an existing entry should be banned
        /// Returns true if the player's trove collateral dropped below threshold OR is over quota
        fn should_ban_entry(
            self: @ContractState,
            tournament_id: u64,
            game_token_id: u64,
            current_owner: ContractAddress,
            qualification: Span<felt252>,
        ) -> bool {
            // Ban if player no longer meets basic trove requirements
            if !self.check_trove_requirements(tournament_id, current_owner) {
                return true;
            }

            // Check if player is over their quota
            let value_per_entry = self.tournament_value_per_entry.read(tournament_id);
            if value_per_entry > 0 {
                // Calculate current allowed entries based on current trove value
                let abbot = IAbbotDispatcher { contract_address: abbot_address() };
                let mut user_troves: Span<u64> = abbot.get_user_trove_ids(current_owner);

                if user_troves.len() == 0 {
                    // No troves = 0 allowed entries, ban all existing entries
                    return true;
                }

                let trove_id: u64 = match user_troves.pop_front() {
                    Option::Some(id) => *id,
                    Option::None => { return true; }, // No trove = ban
                };

                let fdp = IFrontendDataProviderDispatcher { contract_address: fdp_address() };
                let trove_info: TroveInfo = fdp.get_trove_info(trove_id);
                let trove_asset_felt = self.tournament_trove_asset.read(tournament_id);
                let trove_asset: ContractAddress = match trove_asset_felt.try_into() {
                    Option::Some(addr) => addr,
                    Option::None => { return true; }, // Invalid asset = ban
                };

                let mut deposited_value: Wad = Zero::zero();

                // Find the asset in the trove and check its value
                for trove_asset_info in trove_info.assets {
                    if *trove_asset_info.shrine_asset_info.address == trove_asset {
                        deposited_value = *trove_asset_info.value;
                        break;
                    }
                }

                let threshold = self.tournament_trove_threshold.read(tournament_id);
                let threshold_wad: Wad = threshold.into();
                let value_per_entry_wad: Wad = value_per_entry.into();

                let total_allowed_entries = if deposited_value > threshold_wad {
                    let result_wad = (deposited_value - threshold_wad) / value_per_entry_wad;
                    result_wad.val / 1000000000000000000 / 1000000000000000000
                } else {
                    0
                };

                let key = (tournament_id, current_owner);
                let used_entries = self.tournament_entries_per_address.read(key);

                let total_allowed_u8: u8 = match total_allowed_entries.try_into() {
                    Option::Some(val) => val,
                    Option::None => {
                        if total_allowed_entries > 255 {
                            255_u8
                        } else {
                            0
                        }
                    },
                };

                // Apply max entries cap if set
                let max_entries = self.tournament_max_entries.read(tournament_id);
                let final_allowed = if max_entries > 0 && total_allowed_u8 > max_entries {
                    max_entries
                } else {
                    total_allowed_u8
                };

                // Ban if player has more entries than currently allowed
                return used_entries > final_allowed;
            }

            // For fixed entry limits, player shouldn't be over quota
            // (they would have been blocked at entry time)
            false
        }

        fn entries_left(
            self: @ContractState,
            tournament_id: u64,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) -> Option<u8> {
            let value_per_entry = self.tournament_value_per_entry.read(tournament_id);

            if value_per_entry > 0 {
                // Calculate entries based on deposited value
                let abbot = IAbbotDispatcher { contract_address: abbot_address() };
                let mut user_troves: Span<u64> = abbot.get_user_trove_ids(player_address);

                // If user has no troves, they have 0 entries
                if user_troves.len() == 0 {
                    return Option::Some(0);
                }

                let trove_id: u64 = match user_troves.pop_front() {
                    Option::Some(id) => *id,
                    Option::None => { return Option::Some(0); },
                };
                let fdp = IFrontendDataProviderDispatcher { contract_address: fdp_address() };
                let trove_info: TroveInfo = fdp.get_trove_info(trove_id);
                let trove_asset_felt = self.tournament_trove_asset.read(tournament_id);
                let trove_asset: ContractAddress = match trove_asset_felt.try_into() {
                    Option::Some(addr) => addr,
                    Option::None => { return Option::Some(0); },
                };

                let mut deposited_value: Wad = Zero::zero();

                // Find the asset in the trove and check its value
                for trove_asset_info in trove_info.assets {
                    if *trove_asset_info.shrine_asset_info.address == trove_asset {
                        deposited_value = *trove_asset_info.value;
                        break;
                    }
                }

                let threshold = self.tournament_trove_threshold.read(tournament_id);
                let threshold_wad: Wad = threshold.into();
                let value_per_entry_wad: Wad = value_per_entry.into();

                let total_entries = if deposited_value > threshold_wad {
                    let result_wad = (deposited_value - threshold_wad) / value_per_entry_wad;
                    result_wad.val / 1000000000000000000 / 1000000000000000000
                } else {
                    0
                };

                let key = (tournament_id, player_address);
                let used_entries = self.tournament_entries_per_address.read(key);

                let mut total_entries_u8: u8 = match total_entries.try_into() {
                    Option::Some(val) => val,
                    Option::None => {
                        if total_entries > 255 {
                            255_u8
                        } else {
                            return Option::Some(0);
                        }
                    },
                };

                let max_entries = self.tournament_max_entries.read(tournament_id);
                if max_entries > 0 && total_entries_u8 > max_entries {
                    total_entries_u8 = max_entries;
                }

                if total_entries_u8 > used_entries {
                    return Option::Some(total_entries_u8 - used_entries);
                } else {
                    return Option::Some(0);
                }
            } else {
                let entry_limit = self.tournament_entry_limit.read(tournament_id);
                if entry_limit == 0 {
                    return Option::None;
                }
                let key = (tournament_id, player_address);
                let current_entries = self.tournament_entries_per_address.read(key);
                let remaining_entries = entry_limit - current_entries;
                return Option::Some(remaining_entries);
            }
        }

        fn add_config(
            ref self: ContractState, tournament_id: u64, entry_limit: u8, config: Span<felt252>,
        ) {
            let trove_asset: ContractAddress = (*config.at(0)).try_into().unwrap();
            let trove_threshold: u128 = (*config.at(1)).try_into().unwrap();
            let value_per_entry: u128 = if config.len() > 2 {
                (*config.at(2)).try_into().unwrap()
            } else {
                0
            };
            let max_entries: u8 = if config.len() > 3 {
                (*config.at(3)).try_into().unwrap()
            } else {
                0
            };

            self.tournament_trove_asset.write(tournament_id, trove_asset);
            self.tournament_trove_threshold.write(tournament_id, trove_threshold);
            self.tournament_entry_limit.write(tournament_id, entry_limit);
            self.tournament_value_per_entry.write(tournament_id, value_per_entry);
            self.tournament_max_entries.write(tournament_id, max_entries);
        }

        fn on_entry_added(
            ref self: ContractState,
            tournament_id: u64,
            game_token_id: u64,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) {
            let key = (tournament_id, player_address);
            let current_entries = self.tournament_entries_per_address.read(key);
            self.tournament_entries_per_address.write(key, current_entries + 1);
        }

        fn on_entry_removed(
            ref self: ContractState,
            tournament_id: u64,
            game_token_id: u64,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) {
            let key = (tournament_id, player_address);
            let current_entries = self.tournament_entries_per_address.read(key);
            if current_entries > 0 {
                self.tournament_entries_per_address.write(key, current_entries - 1);
            }
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn check_trove_requirements(
            self: @ContractState, tournament_id: u64, player_address: ContractAddress,
        ) -> bool {
            let abbot = IAbbotDispatcher { contract_address: abbot_address() };
            let mut user_troves: Span<u64> = abbot.get_user_trove_ids(player_address);

            if user_troves.len() == 0 {
                return false;
            }

            let trove_id: u64 = *user_troves.pop_front().unwrap();
            let fdp = IFrontendDataProviderDispatcher { contract_address: fdp_address() };
            let trove_info: TroveInfo = fdp.get_trove_info(trove_id);
            let trove_asset_felt = self.tournament_trove_asset.read(tournament_id);
            let trove_asset: ContractAddress = trove_asset_felt.try_into().unwrap();

            let mut deposited_value: Wad = Zero::zero();

            for trove_asset_info in trove_info.assets {
                if *trove_asset_info.shrine_asset_info.address == trove_asset {
                    deposited_value = *trove_asset_info.value;
                    break;
                }
            }

            let threshold = self.tournament_trove_threshold.read(tournament_id);
            let threshold_wad: Wad = threshold.into();
            deposited_value >= threshold_wad
        }

        /// Check if player has entries available (quota not exhausted)
        fn has_entries_available(
            self: @ContractState, tournament_id: u64, player_address: ContractAddress,
        ) -> bool {
            let value_per_entry = self.tournament_value_per_entry.read(tournament_id);

            if value_per_entry > 0 {
                // Check quota based on trove value
                let used_entries = self
                    .tournament_entries_per_address
                    .read((tournament_id, player_address));

                // If no entries used yet, they have entries available (assuming they meet requirements)
                if used_entries == 0 {
                    return true;
                }

                // Calculate current allowed entries
                let abbot = IAbbotDispatcher { contract_address: abbot_address() };
                let mut user_troves: Span<u64> = abbot.get_user_trove_ids(player_address);

                if user_troves.len() == 0 {
                    return false;
                }

                let trove_id: u64 = match user_troves.pop_front() {
                    Option::Some(id) => *id,
                    Option::None => { return false; },
                };

                let fdp = IFrontendDataProviderDispatcher { contract_address: fdp_address() };
                let trove_info: TroveInfo = fdp.get_trove_info(trove_id);
                let trove_asset_felt = self.tournament_trove_asset.read(tournament_id);
                let trove_asset: ContractAddress = match trove_asset_felt.try_into() {
                    Option::Some(addr) => addr,
                    Option::None => { return false; },
                };

                let mut deposited_value: Wad = Zero::zero();

                for trove_asset_info in trove_info.assets {
                    if *trove_asset_info.shrine_asset_info.address == trove_asset {
                        deposited_value = *trove_asset_info.value;
                        break;
                    }
                }

                let threshold = self.tournament_trove_threshold.read(tournament_id);
                let threshold_wad: Wad = threshold.into();
                let value_per_entry_wad: Wad = value_per_entry.into();

                let total_allowed_entries = if deposited_value > threshold_wad {
                    let result_wad = (deposited_value - threshold_wad) / value_per_entry_wad;
                    result_wad.val / 1000000000000000000 / 1000000000000000000
                } else {
                    0
                };

                let total_allowed_u8: u8 = match total_allowed_entries.try_into() {
                    Option::Some(val) => val,
                    Option::None => {
                        if total_allowed_entries > 255 {
                            255_u8
                        } else {
                            0
                        }
                    },
                };

                let max_entries = self.tournament_max_entries.read(tournament_id);
                let final_allowed = if max_entries > 0 && total_allowed_u8 > max_entries {
                    max_entries
                } else {
                    total_allowed_u8
                };

                return used_entries < final_allowed;
            } else {
                // Fixed entry limit mode
                let entry_limit = self.tournament_entry_limit.read(tournament_id);
                if entry_limit == 0 {
                    return true; // Unlimited
                }
                let used_entries = self
                    .tournament_entries_per_address
                    .read((tournament_id, player_address));
                return used_entries < entry_limit;
            }
        }
    }

    // Public interface implementation
    use super::IEntryValidatorMock;
    #[abi(embed_v0)]
    impl EntryValidatorMockImpl of IEntryValidatorMock<ContractState> {
        fn get_trove_asset(self: @ContractState, tournament_id: u64) -> ContractAddress {
            self.tournament_trove_asset.read(tournament_id)
        }

        fn get_trove_threshold(self: @ContractState, tournament_id: u64) -> u128 {
            self.tournament_trove_threshold.read(tournament_id)
        }

        fn get_value_per_entry(self: @ContractState, tournament_id: u64) -> u128 {
            self.tournament_value_per_entry.read(tournament_id)
        }

        fn get_max_entries(self: @ContractState, tournament_id: u64) -> u8 {
            self.tournament_max_entries.read(tournament_id)
        }
    }
}
