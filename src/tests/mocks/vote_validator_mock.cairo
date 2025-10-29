#[starknet::contract]
pub mod entry_validator_mock {
    use budokan_extensions::entry_validator::entry_validator::EntryValidatorComponent;
    use budokan_extensions::entry_validator::entry_validator::EntryValidatorComponent::EntryValidator;
    use openzeppelin_governance::governor::interface::{
        IGovernorDispatcher, IGovernorDispatcherTrait,
    };
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
        governor_address: Map<u64, ContractAddress>,
        proposal_id: Map<u64, felt252>,
        votes_threshold: Map<u64, u256>,
        entry_limit: Map<u64, u8>,
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
    fn constructor(ref self: ContractState) {
        self.entry_validator.initializer();
    }

    // Implement the EntryValidator trait for the contract
    impl EntryValidatorImplInternal of EntryValidator<ContractState> {
        fn validate_entry(
            self: @ContractState,
            tournament_id: u64,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) -> bool {
            // Extract proposal_id from qualification
            let proposal_id = *qualification.at(0);
            let governor_address = self.governor_address.read(tournament_id);
            let governor_dispatcher = IGovernorDispatcher { contract_address: governor_address };
            let has_voted = governor_dispatcher.has_voted(proposal_id, player_address);
            let proposal_snapshot = governor_dispatcher.proposal_snapshot(proposal_id);
            let vote_count = governor_dispatcher.get_votes(player_address, proposal_snapshot);
            let votes_meet_threshold = vote_count >= self.votes_threshold.read(tournament_id);
            has_voted && votes_meet_threshold
        }

        fn entries_left(
            self: @ContractState,
            tournament_id: u64,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) -> Option<u8> {
            let entry_limit = self.entry_limit.read(tournament_id);
            if entry_limit == 0 {
                return Option::None; // Unlimited entries
            }
            let key = (tournament_id, player_address);
            let current_entries = self.tournament_entries_per_address.read(key);
            let remaining_entries = entry_limit - current_entries;
            return Option::Some(remaining_entries);
        }

        fn add_config(ref self: ContractState, tournament_id: u64, config: Span<felt252>) {
            let governor_address: ContractAddress = (*config.at(0)).try_into().unwrap();
            let proposal_id: felt252 = *config.at(1);
            let votes_threshold: u256 = (*config.at(2)).try_into().unwrap();
            let entry_limit: u8 = (*config.at(3)).try_into().unwrap();
            self.governor_address.write(tournament_id, governor_address);
            self.proposal_id.write(tournament_id, proposal_id);
            self.votes_threshold.write(tournament_id, votes_threshold);
            self.entry_limit.write(tournament_id, entry_limit);
        }

        fn add_entry(
            ref self: ContractState,
            tournament_id: u64,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) {
            let key = (tournament_id, player_address);
            let current_entries = self.tournament_entries_per_address.read(key);
            self.tournament_entries_per_address.write(key, current_entries + 1);
        }
    }
}
