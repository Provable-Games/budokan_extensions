#[starknet::contract]
pub mod GovernanceValidator {
    use budokan_entry_requirement::entry_validator::EntryValidatorComponent;
    use budokan_entry_requirement::entry_validator::EntryValidatorComponent::EntryValidator;
    use core::num::traits::Zero;
    use openzeppelin_interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin_interfaces::governor::{IGovernorDispatcher, IGovernorDispatcherTrait};
    use openzeppelin_interfaces::votes::{IVotesDispatcher, IVotesDispatcherTrait};
    use openzeppelin_introspection::src5::SRC5Component;
    use starknet::ContractAddress;
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};

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
        entry_limit: Map<u64, u8>,
        governor_address: Map<u64, ContractAddress>,
        governance_token_address: Map<u64, ContractAddress>,
        balance_threshold: Map<u64, u256>,
        proposal_id: Map<u64, felt252>,
        check_voted: Map<u64, bool>,
        votes_threshold: Map<u64, u256>,
        votes_per_entry: Map<u64, u256>,
        tournament_entries_per_address: Map<(u64, ContractAddress), u8>,
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
        // Governance requirements can change, so registration_only = false (allow banning)
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
            // Must meet governance requirements AND have entries available
            self.check_governance_requirements(tournament_id, player_address)
                && self.has_entries_available(tournament_id, player_address)
        }

        /// Check if an existing entry should be banned
        /// Returns true if the player no longer meets governance requirements OR is over quota
        fn should_ban_entry(
            self: @ContractState,
            tournament_id: u64,
            game_token_id: u64,
            current_owner: ContractAddress,
            qualification: Span<felt252>,
        ) -> bool {
            // Ban if player no longer meets basic governance requirements
            if !self.check_governance_requirements(tournament_id, current_owner) {
                return true;
            }

            // Check if player is over their quota
            let votes_per_entry = self.votes_per_entry.read(tournament_id);
            if votes_per_entry > 0 {
                // Calculate current allowed entries based on current votes
                let proposal_id = self.proposal_id.read(tournament_id);
                let governor_address = self.governor_address.read(tournament_id);
                let governor_dispatcher = IGovernorDispatcher {
                    contract_address: governor_address,
                };
                let proposal_snapshot = governor_dispatcher.proposal_snapshot(proposal_id);
                let vote_count = governor_dispatcher.get_votes(current_owner, proposal_snapshot);
                let balance_threshold = self.balance_threshold.read(tournament_id);
                let total_allowed_entries = (vote_count - balance_threshold) / votes_per_entry;
                let used_entries = self
                    .tournament_entries_per_address
                    .read((tournament_id, current_owner));

                // Ban if player has more entries than currently allowed
                return used_entries > total_allowed_entries.low.try_into().unwrap();
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
            let votes_per_entry = self.votes_per_entry.read(tournament_id);
            if votes_per_entry > 0 {
                // calculate the number of entries based on the votes
                let proposal_id = self.proposal_id.read(tournament_id);
                let governor_address = self.governor_address.read(tournament_id);
                let governor_dispatcher = IGovernorDispatcher {
                    contract_address: governor_address,
                };
                let proposal_snapshot = governor_dispatcher.proposal_snapshot(proposal_id);
                let vote_count = governor_dispatcher.get_votes(player_address, proposal_snapshot);
                let balance_threshold = self.balance_threshold.read(tournament_id);
                let total_entries = (vote_count - balance_threshold) / votes_per_entry;
                let used_entries = self
                    .tournament_entries_per_address
                    .read((tournament_id, player_address));
                let remaining_entries = total_entries.low.try_into().unwrap() - used_entries;
                return Option::Some(remaining_entries);
            } else {
                let entry_limit = self.entry_limit.read(tournament_id);
                if entry_limit == 0 {
                    return Option::None; // Unlimited entries
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
            let governor_address: ContractAddress = (*config.at(0)).try_into().unwrap();
            let governance_token_address: ContractAddress = (*config.at(1)).try_into().unwrap();
            let balance_threshold: u256 = (*config.at(2)).try_into().unwrap();
            let proposal_id: felt252 = *config.at(3);
            let check_voted: bool = (*config.at(4)) != 0;
            let votes_threshold: u256 = (*config.at(5)).try_into().unwrap();
            let votes_per_entry: u256 = (*config.at(6)).try_into().unwrap();

            self.entry_limit.write(tournament_id, entry_limit);
            self.governor_address.write(tournament_id, governor_address);
            self.governance_token_address.write(tournament_id, governance_token_address);
            self.balance_threshold.write(tournament_id, balance_threshold);
            self.proposal_id.write(tournament_id, proposal_id);
            self.check_voted.write(tournament_id, check_voted);
            self.votes_threshold.write(tournament_id, votes_threshold);
            self.votes_per_entry.write(tournament_id, votes_per_entry);
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
        /// Check if a player meets the governance requirements for a tournament
        fn check_governance_requirements(
            self: @ContractState, tournament_id: u64, player_address: ContractAddress,
        ) -> bool {
            // Check the delegate of the address
            let governance_token_address = self.governance_token_address.read(tournament_id);
            let erc20_dispatcher = IERC20Dispatcher { contract_address: governance_token_address };
            let balance = erc20_dispatcher.balance_of(player_address);
            let votes_dispatcher = IVotesDispatcher { contract_address: governance_token_address };
            let delegates = votes_dispatcher.delegates(player_address);

            // If no delegate, or balance below threshold, reject entry
            if delegates.is_zero() || balance < self.balance_threshold.read(tournament_id) {
                return false;
            }

            let check_voted = self.check_voted.read(tournament_id);
            if check_voted {
                let proposal_id = self.proposal_id.read(tournament_id);
                let governor_address = self.governor_address.read(tournament_id);
                let governor_dispatcher = IGovernorDispatcher {
                    contract_address: governor_address,
                };
                let has_voted = governor_dispatcher.has_voted(proposal_id, player_address);
                let proposal_snapshot = governor_dispatcher.proposal_snapshot(proposal_id);
                let vote_count = governor_dispatcher.get_votes(player_address, proposal_snapshot);
                let votes_meet_threshold = vote_count >= self.votes_threshold.read(tournament_id);
                has_voted && votes_meet_threshold
            } else {
                true
            }
        }

        /// Check if player has entries available (quota not exhausted)
        fn has_entries_available(
            self: @ContractState, tournament_id: u64, player_address: ContractAddress,
        ) -> bool {
            let votes_per_entry = self.votes_per_entry.read(tournament_id);
            if votes_per_entry > 0 {
                // Check quota based on votes
                let used_entries = self
                    .tournament_entries_per_address
                    .read((tournament_id, player_address));

                // If no entries used yet, they have entries available
                if used_entries == 0 {
                    return true;
                }

                // Calculate current allowed entries
                let proposal_id = self.proposal_id.read(tournament_id);
                let governor_address = self.governor_address.read(tournament_id);
                let governor_dispatcher = IGovernorDispatcher {
                    contract_address: governor_address,
                };
                let proposal_snapshot = governor_dispatcher.proposal_snapshot(proposal_id);
                let vote_count = governor_dispatcher.get_votes(player_address, proposal_snapshot);
                let balance_threshold = self.balance_threshold.read(tournament_id);
                let total_allowed_entries = (vote_count - balance_threshold) / votes_per_entry;
                let total_allowed_u8: u8 = total_allowed_entries.low.try_into().unwrap();

                return used_entries < total_allowed_u8;
            } else {
                // Fixed entry limit mode
                let entry_limit = self.entry_limit.read(tournament_id);
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
}
