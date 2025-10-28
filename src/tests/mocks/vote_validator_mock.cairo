use starknet::ContractAddress;

#[starknet::interface]
pub trait IEntryValidatorMock<TState> {
    fn governor_address(self: @TState) -> ContractAddress;
}

#[starknet::contract]
pub mod entry_validator_mock {
    use starknet::ContractAddress;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use budokan_extensions::entry_validator::entry_validator::EntryValidatorComponent;
    use budokan_extensions::entry_validator::entry_validator::EntryValidatorComponent::EntryValidator;
    use openzeppelin_introspection::src5::SRC5Component;
    use openzeppelin_governance::governor::interface::{
        IGovernorDispatcher, IGovernorDispatcherTrait,
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
        governor_address: ContractAddress,
        votes_threshold: u256,
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
    fn constructor(
        ref self: ContractState, governor_address: ContractAddress, votes_threshold: u256,
    ) {
        self.entry_validator.initializer();
        self.governor_address.write(governor_address);
        self.votes_threshold.write(votes_threshold);
    }

    // Implement the EntryValidator trait for the contract
    impl EntryValidatorImplInternal of EntryValidator<ContractState> {
        fn add_config(ref self: ContractState, tournament_id: u64, config: Span<felt252>) {// Vote validator uses constructor params, doesn't need dynamic config
        // This is a no-op
        }

        fn validate_entry(
            self: @ContractState,
            tournament_id: u64,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) -> bool {
            // Extract proposal_id from qualification
            let proposal_id = *qualification.at(0);
            let governor_address = self.governor_address.read();
            let governor_dispatcher = IGovernorDispatcher { contract_address: governor_address };
            let has_voted = governor_dispatcher.has_voted(proposal_id, player_address);
            let proposal_snapshot = governor_dispatcher.proposal_snapshot(proposal_id);
            let vote_count = governor_dispatcher.get_votes(player_address, proposal_snapshot);
            let votes_meet_threshold = vote_count >= self.votes_threshold.read();
            has_voted && votes_meet_threshold
        }
    }

    // Public interface implementation
    use super::IEntryValidatorMock;
    #[abi(embed_v0)]
    impl EntryValidatorMockImpl of IEntryValidatorMock<ContractState> {
        fn governor_address(self: @ContractState) -> ContractAddress {
            self.governor_address.read()
        }
    }
}
