//! Opus Troves Validator - Debt Based
//!
//! This validator calculates tournament entries based on borrowed yin (stablecoin) from Opus Protocol.
//! Players with active debt positions can enter tournaments, with entries scaling based on amount borrowed.
//!
//! ## How It Works:
//! - Sums debt across ALL troves owned by a player
//! - Calculates entries: (total_debt - threshold) / value_per_entry
//! - Forging more yin → more entries
//! - Melting yin → fewer entries (can trigger banning if over quota)
//!
//! ## Configuration (via add_config):
//! - config[0]: asset_count (u8) - 0 = wildcard (all troves), N = filter by N assets
//! - config[1..N]: asset addresses (troves must contain at least one)
//! - config[N+1]: threshold (u128) - minimum yin debt to qualify (WAD UNITS: 1e18 = 1 yin)
//! - config[N+2]: value_per_entry (u128) - yin required per entry (WAD UNITS: 1e18 = 1 yin)
//! - config[N+3]: max_entries (u8) - maximum entries cap (0 = no cap)
//!
//! **IMPORTANT**: threshold and value_per_entry use WAD UNITS (18 decimals).
//! 1 yin = 1000000000000000000 (1e18). This gives maximum precision and control.
//!
//! ## Examples:
//!
//! ### Example 1: Wildcard - All borrowers (1 yin per entry)
//! ```
//! config = [0, 1000000000000000000, 1000000000000000000, 0]
//! // 0 assets (wildcard), 1 yin threshold, 1 yin per entry, no max
//! → Counts debt from ALL troves regardless of collateral
//! → Player with 3.5 yin debt gets (3.5e18 - 1e18) / 1e18 = 2 entries
//! ```
//!
//! ### Example 2: STRK borrowers only (0.5 yin per entry)
//! ```
//! config = [1, STRK_ADDRESS, 10000000000000000000, 500000000000000000, 10]
//! // 1 asset filter, 10 yin threshold, 0.5 yin per entry, max 10
//! → Only counts debt from troves backed by STRK
//! → Player with 30 yin debt gets (30e18 - 10e18) / 0.5e18 = 40 entries (capped at 10)
//! ```
//!
//! ### Example 3: Blue chip borrowers (2 yin per entry)
//! ```
//! config = [2, STRK_ADDRESS, WSTETH_ADDRESS, 5000000000000000000, 2000000000000000000, 0]
//! // 2 assets, 5 yin threshold, 2 yin per entry, no max
//! → Counts debt from troves backed by STRK OR wstETH
//! → Player with 25 yin debt gets (25e18 - 5e18) / 2e18 = 10 entries
//! ```

use starknet::ContractAddress;
use wadray::Wad;

#[starknet::interface]
pub trait IAbbot<TContractState> {
    fn get_trove_owner(self: @TContractState, trove_id: u64) -> Option<ContractAddress>;
    fn get_user_trove_ids(self: @TContractState, user: ContractAddress) -> Span<u64>;
    fn get_troves_count(self: @TContractState) -> u64;
    fn get_trove_asset_balance(self: @TContractState, trove_id: u64, yang: ContractAddress) -> u128;
}

#[starknet::interface]
pub trait IShrine<TContractState> {
    fn get_trove_health(self: @TContractState, trove_id: u64) -> Health;
}

#[derive(Drop, Serde, Copy)]
pub struct Health {
    pub threshold: wadray::Ray,
    pub ltv: wadray::Ray,
    pub value: Wad,
    pub debt: Wad,
}

#[starknet::interface]
pub trait IOpusTrovesValidator<TState> {
    fn get_debt_threshold(self: @TState, tournament_id: u64) -> u128;
    fn get_value_per_entry(self: @TState, tournament_id: u64) -> u128;
    fn get_max_entries(self: @TState, tournament_id: u64) -> u8;
}

#[starknet::contract]
pub mod OpusTrovesValidator {
    use budokan_entry_requirement::entry_validator::EntryValidatorComponent;
    use budokan_entry_requirement::entry_validator::EntryValidatorComponent::EntryValidator;
    use core::num::traits::Zero;
    use openzeppelin_introspection::src5::SRC5Component;
    use starknet::ContractAddress;
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};
    use wadray::Wad;
    use super::{
        IAbbotDispatcher, IAbbotDispatcherTrait, IShrineDispatcher, IShrineDispatcherTrait, Health,
    };

    // Opus mainnet addresses
    fn abbot_address() -> ContractAddress {
        0x04d0bb0a4c40012384e7c419e6eb3c637b28e8363fb66958b60d90505b9c072f.try_into().unwrap()
    }

    fn shrine_address() -> ContractAddress {
        0x0498edfaf50ca5855666a700c25dd629d577eb9afccdf3b5977aec79aee55ada.try_into().unwrap()
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
        // Asset filtering (0 = wildcard, N = filter by N assets)
        tournament_asset_count: Map<u64, u8>,
        // Asset addresses for filtering (tournament_id, index) -> address
        tournament_assets: Map<(u64, u8), ContractAddress>,
        // Minimum debt threshold to qualify
        tournament_debt_threshold: Map<u64, u128>,
        // Fixed entry limit (0 = use value_per_entry instead)
        tournament_entry_limit: Map<u64, u8>,
        // Entry count per player
        tournament_entries_per_address: Map<(u64, ContractAddress), u8>,
        // Debt required per entry (0 = use fixed limit)
        tournament_value_per_entry: Map<u64, u128>,
        // Maximum entries cap (0 = no cap)
        tournament_max_entries: Map<u64, u8>,
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
        // Trove collateral/debt can change, so registration_only = true (allow banning)
        self.entry_validator.initializer(budokan_address, true);
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
        /// Returns true if the player's trove no longer meets requirements OR is over quota
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
                let (total_allowed_entries, _) = self
                    .calculate_entries_from_trove(tournament_id, current_owner);

                let used_entries = self
                    .tournament_entries_per_address
                    .read((tournament_id, current_owner));

                // Ban if player has more entries than currently allowed
                return used_entries > total_allowed_entries;
            }

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
                let (total_entries_u8, _) = self
                    .calculate_entries_from_trove(tournament_id, player_address);
                let used_entries = self
                    .tournament_entries_per_address
                    .read((tournament_id, player_address));

                if total_entries_u8 > used_entries {
                    return Option::Some(total_entries_u8 - used_entries);
                } else {
                    return Option::Some(0);
                }
            } else {
                // Fixed entry limit mode
                let entry_limit = self.tournament_entry_limit.read(tournament_id);
                if entry_limit == 0 {
                    return Option::None;
                }
                let used_entries = self
                    .tournament_entries_per_address
                    .read((tournament_id, player_address));
                let remaining_entries = entry_limit - used_entries;
                return Option::Some(remaining_entries);
            }
        }

        fn add_config(
            ref self: ContractState, tournament_id: u64, entry_limit: u8, config: Span<felt252>,
        ) {
            // Config format:
            // [0]: asset_count (u8) - 0 = wildcard, N = filter by N assets
            // [1..N]: asset addresses (if asset_count > 0)
            // [N+1]: threshold (u128) - minimum yin debt to qualify
            // [N+2]: value_per_entry (u128) - yin required per entry
            // [N+3]: max_entries (u8) - maximum entries cap (0 = no cap)

            let asset_count: u8 = (*config.at(0)).try_into().unwrap();
            self.tournament_asset_count.write(tournament_id, asset_count);

            // Parse asset addresses
            let mut i: u8 = 0;
            loop {
                if i >= asset_count {
                    break;
                }
                let asset_address: ContractAddress = (*config.at((1 + i).into()))
                    .try_into()
                    .unwrap();
                self.tournament_assets.write((tournament_id, i), asset_address);
                i += 1;
            };

            // Parse remaining config (offset by asset_count)
            let offset: usize = (1 + asset_count).into();
            let threshold: u128 = (*config.at(offset)).try_into().unwrap();
            let value_per_entry: u128 = if config.len() > offset + 1 {
                (*config.at(offset + 1)).try_into().unwrap()
            } else {
                0
            };
            let max_entries: u8 = if config.len() > offset + 2 {
                (*config.at(offset + 2)).try_into().unwrap()
            } else {
                0
            };

            self.tournament_debt_threshold.write(tournament_id, threshold);
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
        /// Check if a trove matches the asset filter for a tournament
        /// Returns true if asset_count=0 (wildcard) or trove contains at least one specified asset
        fn trove_matches_asset_filter(
            self: @ContractState, tournament_id: u64, trove_id: u64,
        ) -> bool {
            let asset_count = self.tournament_asset_count.read(tournament_id);

            // Wildcard mode: accept all troves
            if asset_count == 0 {
                return true;
            }

            // Check if trove has any of the specified assets
            let abbot = IAbbotDispatcher { contract_address: abbot_address() };
            let mut i: u8 = 0;
            loop {
                if i >= asset_count {
                    break;
                }

                let asset_address = self.tournament_assets.read((tournament_id, i));
                let balance = abbot.get_trove_asset_balance(trove_id, asset_address);

                // If trove has this asset, it matches the filter
                if balance > 0 {
                    return true;
                }

                i += 1;
            };

            // No matching assets found
            false
        }

        /// Check if a player meets the debt threshold for a tournament
        /// Sums debt across filtered troves (based on asset requirements)
        fn check_trove_requirements(
            self: @ContractState, tournament_id: u64, player_address: ContractAddress,
        ) -> bool {
            let abbot = IAbbotDispatcher { contract_address: abbot_address() };
            let mut user_troves: Span<u64> = abbot.get_user_trove_ids(player_address);

            if user_troves.len() == 0 {
                return false;
            }

            let threshold = self.tournament_debt_threshold.read(tournament_id);
            let shrine = IShrineDispatcher { contract_address: shrine_address() };

            // Sum debt across filtered troves (in wad units)
            let mut total_debt: u128 = 0;
            loop {
                match user_troves.pop_front() {
                    Option::Some(trove_id) => {
                        // Check if trove matches asset filter
                        if !self.trove_matches_asset_filter(tournament_id, *trove_id) {
                            continue;
                        }

                        let health: Health = shrine.get_trove_health(*trove_id);
                        // Keep debt in wad units (18 decimals) for maximum precision
                        total_debt += health.debt.val;
                    },
                    Option::None => { break; },
                }
            };

            total_debt >= threshold
        }

        /// Check if player has entries available (quota not exhausted)
        fn has_entries_available(
            self: @ContractState, tournament_id: u64, player_address: ContractAddress,
        ) -> bool {
            let value_per_entry = self.tournament_value_per_entry.read(tournament_id);

            if value_per_entry > 0 {
                let used_entries = self
                    .tournament_entries_per_address
                    .read((tournament_id, player_address));

                if used_entries == 0 {
                    return true;
                }

                let (total_allowed_entries, _) = self
                    .calculate_entries_from_trove(tournament_id, player_address);
                return used_entries < total_allowed_entries;
            } else {
                // Fixed entry limit mode
                let entry_limit = self.tournament_entry_limit.read(tournament_id);
                if entry_limit == 0 {
                    return true;
                }
                let used_entries = self
                    .tournament_entries_per_address
                    .read((tournament_id, player_address));
                return used_entries < entry_limit;
            }
        }

        /// Calculate entries from filtered troves
        /// Sums debt across filtered troves (based on asset requirements)
        /// Returns (capped_entries_u8, total_debt_wad)
        fn calculate_entries_from_trove(
            self: @ContractState, tournament_id: u64, player_address: ContractAddress,
        ) -> (u8, Wad) {
            let abbot = IAbbotDispatcher { contract_address: abbot_address() };
            let mut user_troves: Span<u64> = abbot.get_user_trove_ids(player_address);

            if user_troves.len() == 0 {
                return (0, Zero::zero());
            }

            let threshold = self.tournament_debt_threshold.read(tournament_id);
            let value_per_entry = self.tournament_value_per_entry.read(tournament_id);
            let shrine = IShrineDispatcher { contract_address: shrine_address() };

            // Sum debt across filtered troves (in wad units)
            let mut total_debt_wad: u128 = 0;
            loop {
                match user_troves.pop_front() {
                    Option::Some(trove_id) => {
                        // Check if trove matches asset filter
                        if !self.trove_matches_asset_filter(tournament_id, *trove_id) {
                            continue;
                        }

                        let health: Health = shrine.get_trove_health(*trove_id);
                        // Keep debt in wad units (18 decimals) for maximum precision
                        total_debt_wad += health.debt.val;
                    },
                    Option::None => { break; },
                }
            };

            // Calculate total entries based on total debt (all in wad units)
            let total_entries: u128 = if total_debt_wad > threshold {
                (total_debt_wad - threshold) / value_per_entry
            } else {
                0
            };

            // Convert to u8 with cap at 255
            let mut total_entries_u8: u8 = match total_entries.try_into() {
                Option::Some(val) => val,
                Option::None => {
                    if total_entries > 255 {
                        255_u8
                    } else {
                        0
                    }
                },
            };

            // Apply max entries cap if set
            let max_entries = self.tournament_max_entries.read(tournament_id);
            if max_entries > 0 && total_entries_u8 > max_entries {
                total_entries_u8 = max_entries;
            }

            // Return entries and total debt as Wad
            let total_debt_wad_type: Wad = Wad { val: total_debt_wad };
            (total_entries_u8, total_debt_wad_type)
        }
    }

    // Public interface implementation
    use super::IOpusTrovesValidator;
    #[abi(embed_v0)]
    impl OpusTrovesValidatorImpl of IOpusTrovesValidator<ContractState> {
        fn get_debt_threshold(self: @ContractState, tournament_id: u64) -> u128 {
            self.tournament_debt_threshold.read(tournament_id)
        }

        fn get_value_per_entry(self: @ContractState, tournament_id: u64) -> u128 {
            self.tournament_value_per_entry.read(tournament_id)
        }

        fn get_max_entries(self: @ContractState, tournament_id: u64) -> u8 {
            self.tournament_max_entries.read(tournament_id)
        }
    }
}
