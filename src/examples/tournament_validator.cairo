// SPDX-License-Identifier: BUSL-1.1

//! Tournament Validator
//!
//! This extension contract validates tournament entry based on participation/winning
//! in qualifying tournaments. It delegates to an external contract (Budokan) to query
//! registration and leaderboard data.
//!
//! Qualifying Modes:
//! - PER_TOKEN (0): Each qualifying token grants `entry_limit` entries (like a "punch card").
//!   Entries are tracked per token. Transfer-safe without banning.
//! - ALL (1): Must qualify from ALL tournaments. Player gets `entry_limit` entries total.
//!   Entries tracked per player. Tokens marked as "used" to prevent reuse (ban tech).
//!
//! Configuration (via add_config):
//! - config[0]: qualifier_type (0 = participants, 1 = top_position)
//! - config[1]: qualifying_mode (0 = PER_TOKEN, 1 = ALL)
//! - config[2]: top_positions (for QUALIFIER_TYPE_TOP_POSITION: how many top positions count as
//! winners, 0 = all positions)
//! - config[3..]: qualifying tournament IDs
//!
//! Qualification proof (via valid_entry qualification param):
//! For PER_TOKEN mode:
//! - qualification[0]: qualifying tournament ID
//! - qualification[1]: token ID used in qualifying tournament
//! - qualification[2]: position on leaderboard (for top_position type, optional)
//!
//! For ALL mode:
//! For PARTICIPANTS: token IDs in same order as qualifying tournament IDs
//! - qualification[0..n]: token IDs for each qualifying tournament
//! For TOP_POSITION: pairs of (token_id, position) for each qualifying tournament
//! - qualification[0]: token_id_1, qualification[1]: position_1, etc.

pub const QUALIFIER_TYPE_PARTICIPANTS: felt252 = 0;
pub const QUALIFIER_TYPE_TOP_POSITION: felt252 = 1;

pub const QUALIFYING_MODE_PER_TOKEN: felt252 = 0;
pub const QUALIFYING_MODE_ALL: felt252 = 1;

#[starknet::interface]
pub trait ITournamentValidator<TState> {
    fn get_qualifier_type(self: @TState, tournament_id: u64) -> felt252;
    fn get_qualifying_mode(self: @TState, tournament_id: u64) -> felt252;
    fn get_qualifying_tournament_ids(self: @TState, tournament_id: u64) -> Array<u64>;
    fn get_top_positions(self: @TState, tournament_id: u64) -> u32;
}

#[starknet::contract]
pub mod TournamentValidator {
    use budokan_entry_requirement::entry_validator::EntryValidatorComponent;
    use budokan_entry_requirement::entry_validator::EntryValidatorComponent::EntryValidator;
    use budokan_interfaces::budokan::{IBudokanDispatcher, IBudokanDispatcherTrait, Phase};
    use budokan_interfaces::registration::{IRegistrationDispatcher, IRegistrationDispatcherTrait};
    use game_components_minigame::interface::{IMinigameDispatcher, IMinigameDispatcherTrait};
    use openzeppelin_interfaces::erc721::{IERC721Dispatcher, IERC721DispatcherTrait};
    use openzeppelin_introspection::src5::SRC5Component;
    use starknet::ContractAddress;
    use starknet::storage::{
        Map, MutableVecTrait, StorageMapReadAccess, StorageMapWriteAccess, StoragePathEntry,
        StoragePointerReadAccess, Vec, VecTrait,
    };
    use super::{
        QUALIFIER_TYPE_PARTICIPANTS, QUALIFIER_TYPE_TOP_POSITION, QUALIFYING_MODE_ALL,
        QUALIFYING_MODE_PER_TOKEN,
    };

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
        /// Qualifier type per tournament (0 = participants, 1 = top_position)
        qualifier_type: Map<u64, felt252>,
        /// Qualifying mode per tournament (0 = PER_TOKEN, 1 = ALL)
        qualifying_mode: Map<u64, felt252>,
        /// Qualifying tournament IDs per tournament
        qualifying_tournament_ids: Map<u64, Vec<u64>>,
        /// Entry limit per tournament
        tournament_entry_limit: Map<u64, u8>,
        /// Top positions that count as winners (0 = all positions)
        top_positions: Map<u64, u32>,
        /// Entry count per (tournament_id, qualifying_token_id) - for PER_TOKEN mode
        token_entries: Map<(u64, u64), u8>,
        /// Entry count per (tournament_id, player_address) - for ALL mode
        player_entries: Map<(u64, ContractAddress), u8>,
        /// Used tokens per (tournament_id, qualifying_token_id) - for ALL mode ban tech
        used_tokens: Map<(u64, u64), bool>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        EntryValidatorEvent: EntryValidatorComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        ConfigAdded: ConfigAdded,
        EntryRecorded: EntryRecorded,
    }

    #[derive(Drop, starknet::Event)]
    struct ConfigAdded {
        tournament_id: u64,
        qualifier_type: felt252,
        qualifying_mode: felt252,
    }

    #[derive(Drop, starknet::Event)]
    struct EntryRecorded {
        tournament_id: u64,
        qualifying_token_id: u64,
        entries_used: u8,
    }

    #[constructor]
    fn constructor(ref self: ContractState, budokan_address: ContractAddress) {
        // Tournament qualification is validated at registration time
        // Once registered, the entry remains valid (registration_only = true)
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
            self.validate_entry_internal(tournament_id, player_address, qualification)
        }

        /// Tournament entries should never be banned after registration
        /// The qualification (owning a token from previous tournament) was valid at registration
        fn should_ban_entry(
            self: @ContractState,
            tournament_id: u64,
            game_token_id: u64,
            current_owner: ContractAddress,
            qualification: Span<felt252>,
        ) -> bool {
            // Never ban tournament entries - they were valid at registration time
            false
        }

        fn entries_left(
            self: @ContractState,
            tournament_id: u64,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) -> Option<u8> {
            // First, validate that the qualification is actually valid
            let is_valid = self
                .validate_entry_internal(tournament_id, player_address, qualification);
            if !is_valid {
                return Option::Some(0); // Invalid qualification = 0 entries
            }

            let entry_limit = self.tournament_entry_limit.read(tournament_id);
            if entry_limit == 0 {
                return Option::None; // Unlimited entries
            }

            let qualifying_mode = self.qualifying_mode.read(tournament_id);

            if qualifying_mode == QUALIFYING_MODE_ALL {
                // ALL mode: entries tracked per player
                // Check if this player has any entries used (meaning they own these tokens)
                let key = (tournament_id, player_address);
                let current_entries = self.player_entries.read(key);

                // If tokens are used but this player hasn't used any entries,
                // it means someone else used these tokens (transfer exploit blocked)
                if current_entries == 0 {
                    let tokens_used = self.check_any_token_used(tournament_id, qualification);
                    if tokens_used {
                        return Option::Some(0); // Tokens used by someone else
                    }
                }

                let remaining_entries = entry_limit - current_entries;
                return Option::Some(remaining_entries);
            } else {
                // PER_TOKEN mode: entries tracked per qualifying token
                let qualifying_token_id: u64 = (*qualification.at(1)).try_into().unwrap();

                let key = (tournament_id, qualifying_token_id);
                let current_entries = self.token_entries.read(key);
                let remaining_entries = entry_limit - current_entries;
                return Option::Some(remaining_entries);
            }
        }

        fn add_config(
            ref self: ContractState, tournament_id: u64, entry_limit: u8, config: Span<felt252>,
        ) {
            // config[0]: qualifier_type (0 = participants, 1 = top_position)
            // config[1]: qualifying_mode (0 = PER_TOKEN, 1 = ALL)
            // config[2]: top_positions (0 = all positions, or number of top positions for
            // top_position type)
            // config[3..]: qualifying tournament IDs
            assert!(
                config.len() >= 4,
                "Config must have qualifier_type, qualifying_mode, top_positions, and at least one tournament ID",
            );

            let qualifier_type = *config.at(0);
            assert!(
                qualifier_type == QUALIFIER_TYPE_PARTICIPANTS
                    || qualifier_type == QUALIFIER_TYPE_TOP_POSITION,
                "Invalid qualifier type",
            );

            let qualifying_mode = *config.at(1);
            assert!(
                qualifying_mode == QUALIFYING_MODE_PER_TOKEN
                    || qualifying_mode == QUALIFYING_MODE_ALL,
                "Invalid qualifying mode",
            );

            let top_positions: u32 = (*config.at(2)).try_into().unwrap();

            self.qualifier_type.write(tournament_id, qualifier_type);
            self.qualifying_mode.write(tournament_id, qualifying_mode);
            self.tournament_entry_limit.write(tournament_id, entry_limit);
            self.top_positions.write(tournament_id, top_positions);

            // Store qualifying tournament IDs
            let mut vec = self.qualifying_tournament_ids.entry(tournament_id);
            let mut i: u32 = 3;
            loop {
                if i >= config.len() {
                    break;
                }
                let qualifying_id: u64 = (*config.at(i)).try_into().unwrap();
                vec.push(qualifying_id);
                i += 1;
            }

            self.emit(ConfigAdded { tournament_id, qualifier_type, qualifying_mode });
        }

        fn on_entry_added(
            ref self: ContractState,
            tournament_id: u64,
            game_token_id: u64,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) {
            let qualifying_mode = self.qualifying_mode.read(tournament_id);

            if qualifying_mode == QUALIFYING_MODE_ALL {
                // ALL mode: track entries per player and mark all tokens as used
                let key = (tournament_id, player_address);
                let current_entries = self.player_entries.read(key);
                self.player_entries.write(key, current_entries + 1);

                // Mark all tokens in the proof as used
                self.mark_tokens_as_used(tournament_id, qualification);

                // Emit with first token as the qualifying token for the event
                let first_token: u64 = (*qualification.at(0)).try_into().unwrap();
                self
                    .emit(
                        EntryRecorded {
                            tournament_id, qualifying_token_id: first_token, entries_used: current_entries + 1,
                        },
                    );
            } else {
                // PER_TOKEN mode: track entries per qualifying token
                let qualifying_token_id: u64 = (*qualification.at(1)).try_into().unwrap();

                let key = (tournament_id, qualifying_token_id);
                let current_entries = self.token_entries.read(key);
                self.token_entries.write(key, current_entries + 1);

                self
                    .emit(
                        EntryRecorded {
                            tournament_id, qualifying_token_id, entries_used: current_entries + 1,
                        },
                    );
            }
        }

        fn on_entry_removed(
            ref self: ContractState,
            tournament_id: u64,
            game_token_id: u64,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) {
            let qualifying_mode = self.qualifying_mode.read(tournament_id);

            if qualifying_mode == QUALIFYING_MODE_ALL {
                // ALL mode: decrement player entries
                // Note: we don't unmark tokens as used - once used, always used
                let key = (tournament_id, player_address);
                let current_entries = self.player_entries.read(key);
                if current_entries > 0 {
                    self.player_entries.write(key, current_entries - 1);
                }
            } else {
                // PER_TOKEN mode: decrement token entries
                let qualifying_token_id: u64 = (*qualification.at(1)).try_into().unwrap();

                let key = (tournament_id, qualifying_token_id);
                let current_entries = self.token_entries.read(key);
                if current_entries > 0 {
                    self.token_entries.write(key, current_entries - 1);
                }
            }
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn validate_entry_internal(
            self: @ContractState,
            tournament_id: u64,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) -> bool {
            let qualifying_mode = self.qualifying_mode.read(tournament_id);

            if qualifying_mode == QUALIFYING_MODE_ALL {
                return self.validate_all_tournaments(tournament_id, player_address, qualification);
            } else {
                return self
                    .validate_single_tournament(tournament_id, player_address, qualification);
            }
        }

        /// Validate for PER_TOKEN mode: player qualifies from a single tournament
        fn validate_single_tournament(
            self: @ContractState,
            tournament_id: u64,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) -> bool {
            // qualification[0]: qualifying tournament ID
            // qualification[1]: token ID used in qualifying tournament
            // qualification[2]: position on leaderboard (for top_position type, optional)
            if qualification.len() < 2 {
                return false;
            }

            let qualifying_tournament_id: u64 = (*qualification.at(0)).try_into().unwrap();
            let token_id: u64 = (*qualification.at(1)).try_into().unwrap();

            // Check if qualifying tournament is in the valid set
            if !self.is_qualifying_tournament(tournament_id, qualifying_tournament_id) {
                return false;
            }

            self
                .validate_token_participation(
                    tournament_id, qualifying_tournament_id, token_id, player_address, qualification, 2,
                )
        }

        /// Validate for ALL mode: player must qualify from ALL tournaments
        fn validate_all_tournaments(
            self: @ContractState,
            tournament_id: u64,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) -> bool {
            let qualifying_tournaments = self.get_qualifying_tournament_ids(tournament_id);
            let num_tournaments: u32 = qualifying_tournaments.len();

            if num_tournaments == 0 {
                return false;
            }

            let qualifier_type = self.qualifier_type.read(tournament_id);

            // Validate qualification proof length
            if qualifier_type == QUALIFIER_TYPE_TOP_POSITION {
                // For top_position: need (token_id, position) pairs
                if qualification.len() != num_tournaments * 2 {
                    return false;
                }
            } else {
                // For participants: need one token_id per tournament
                if qualification.len() != num_tournaments {
                    return false;
                }
            }

            // Validate each tournament
            let mut i: u32 = 0;
            loop {
                if i >= num_tournaments {
                    break true;
                }

                let qualifying_tournament_id = *qualifying_tournaments.at(i);

                if qualifier_type == QUALIFIER_TYPE_TOP_POSITION {
                    let token_id: u64 = (*qualification.at(i * 2)).try_into().unwrap();
                    let mut temp_qual = ArrayTrait::new();
                    temp_qual.append(*qualification.at(i * 2)); // token_id
                    temp_qual.append(*qualification.at(i * 2 + 1)); // position

                    if !self
                        .validate_token_participation(
                            tournament_id,
                            qualifying_tournament_id,
                            token_id,
                            player_address,
                            temp_qual.span(),
                            1,
                        ) {
                        break false;
                    }
                } else {
                    let token_id: u64 = (*qualification.at(i)).try_into().unwrap();

                    if !self
                        .validate_token_participation(
                            tournament_id,
                            qualifying_tournament_id,
                            token_id,
                            player_address,
                            array![].span(),
                            0,
                        ) {
                        break false;
                    }
                }

                i += 1;
            }
        }

        /// Validate that a player owns a token and it's registered in a qualifying tournament
        fn validate_token_participation(
            self: @ContractState,
            tournament_id: u64,
            qualifying_tournament_id: u64,
            token_id: u64,
            player_address: ContractAddress,
            qualification: Span<felt252>,
            position_index: u32,
        ) -> bool {
            let budokan_address = self.entry_validator.get_budokan_address();
            let budokan = IBudokanDispatcher { contract_address: budokan_address };
            let registration_dispatcher = IRegistrationDispatcher {
                contract_address: budokan_address,
            };

            let qualifying_tournament = budokan.tournament(qualifying_tournament_id);
            let game_address = qualifying_tournament.game_config.address;

            // Check registration exists
            let registration = registration_dispatcher.get_registration(game_address, token_id);
            if registration.entry_number == 0
                || registration.context_id != qualifying_tournament_id {
                return false;
            }

            // Check token ownership
            let game_dispatcher = IMinigameDispatcher { contract_address: game_address };
            let game_token_address = game_dispatcher.token_address();
            let erc721 = IERC721Dispatcher { contract_address: game_token_address };
            let token_owner = erc721.owner_of(token_id.into());

            if token_owner != player_address {
                return false;
            }

            let qualifier_type = self.qualifier_type.read(tournament_id);

            if qualifier_type == QUALIFIER_TYPE_TOP_POSITION {
                // Tournament must be finalized
                let current_phase = budokan.current_phase(qualifying_tournament_id);
                if current_phase != Phase::Finalized {
                    return false;
                }

                if !registration.has_submitted {
                    return false;
                }

                if qualification.len() <= position_index {
                    return false;
                }
                let position: u8 = (*qualification.at(position_index)).try_into().unwrap();
                if position == 0 {
                    return false;
                }

                let top_positions = self.top_positions.read(tournament_id);
                if top_positions > 0 && position.into() > top_positions {
                    return false;
                }

                let leaderboard = budokan.get_leaderboard(qualifying_tournament_id);
                if position.into() > leaderboard.len() {
                    return false;
                }

                let leaderboard_token_id = *leaderboard.at((position - 1).into());
                if leaderboard_token_id != token_id {
                    return false;
                }

                return true;
            } else {
                return true;
            }
        }

        fn is_qualifying_tournament(
            self: @ContractState, tournament_id: u64, qualifying_tournament_id: u64,
        ) -> bool {
            let vec = self.qualifying_tournament_ids.entry(tournament_id);
            let len = vec.len();
            let mut i: u64 = 0;
            loop {
                if i >= len {
                    break false;
                }
                if vec.at(i).read() == qualifying_tournament_id {
                    break true;
                }
                i += 1;
            }
        }

        /// Check if any token in the qualification proof is already used (for ALL mode ban tech)
        fn check_any_token_used(
            self: @ContractState, tournament_id: u64, qualification: Span<felt252>,
        ) -> bool {
            let qualifier_type = self.qualifier_type.read(tournament_id);
            let qualifying_tournaments = self.get_qualifying_tournament_ids(tournament_id);
            let num_tournaments: u32 = qualifying_tournaments.len();

            let mut i: u32 = 0;
            loop {
                if i >= num_tournaments {
                    break false;
                }

                let token_id: u64 = if qualifier_type == QUALIFIER_TYPE_TOP_POSITION {
                    (*qualification.at(i * 2)).try_into().unwrap()
                } else {
                    (*qualification.at(i)).try_into().unwrap()
                };

                if self.used_tokens.read((tournament_id, token_id)) {
                    break true;
                }

                i += 1;
            }
        }

        /// Mark all tokens in the qualification proof as used (for ALL mode ban tech)
        fn mark_tokens_as_used(
            ref self: ContractState, tournament_id: u64, qualification: Span<felt252>,
        ) {
            let qualifier_type = self.qualifier_type.read(tournament_id);
            let qualifying_tournaments = self.get_qualifying_tournament_ids(tournament_id);
            let num_tournaments: u32 = qualifying_tournaments.len();

            let mut i: u32 = 0;
            loop {
                if i >= num_tournaments {
                    break;
                }

                let token_id: u64 = if qualifier_type == QUALIFIER_TYPE_TOP_POSITION {
                    (*qualification.at(i * 2)).try_into().unwrap()
                } else {
                    (*qualification.at(i)).try_into().unwrap()
                };

                self.used_tokens.write((tournament_id, token_id), true);

                i += 1;
            }
        }
    }

    // Public interface implementation
    use super::ITournamentValidator;
    #[abi(embed_v0)]
    impl TournamentValidatorImpl of ITournamentValidator<ContractState> {
        fn get_qualifier_type(self: @ContractState, tournament_id: u64) -> felt252 {
            self.qualifier_type.read(tournament_id)
        }

        fn get_qualifying_mode(self: @ContractState, tournament_id: u64) -> felt252 {
            self.qualifying_mode.read(tournament_id)
        }

        fn get_qualifying_tournament_ids(self: @ContractState, tournament_id: u64) -> Array<u64> {
            let vec = self.qualifying_tournament_ids.entry(tournament_id);
            let len = vec.len();
            let mut arr = ArrayTrait::new();
            let mut i: u64 = 0;
            loop {
                if i >= len {
                    break;
                }
                arr.append(vec.at(i).read());
                i += 1;
            }
            arr
        }

        fn get_top_positions(self: @ContractState, tournament_id: u64) -> u32 {
            self.top_positions.read(tournament_id)
        }
    }
}
