#[starknet::contract]
pub mod open_entry_validator_mock {
    use budokan_extensions::entry_validator::entry_validator::EntryValidatorComponent;
    use budokan_extensions::entry_validator::entry_validator::EntryValidatorComponent::EntryValidator;
    use openzeppelin_introspection::src5::SRC5Component;
    use starknet::ContractAddress;

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

    // Implement the EntryValidator trait - always returns true (open to everyone)
    impl OpenEntryValidatorImpl of EntryValidator<ContractState> {
        fn validate_entry(
            self: @ContractState,
            tournament_id: u64,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) -> bool {
            // Open validator: everyone can enter regardless of tournament
            true
        }

        fn entries_left(
            self: @ContractState,
            tournament_id: u64,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) -> Option<u8> {
            // Open validator: unlimited entries
            Option::None
        }

        fn add_config(
            ref self: ContractState, tournament_id: u64, config: Span<felt252>,
        ) { // Open validator doesn't need configuration
        // This is a no-op
        }

        fn add_entry(
            ref self: ContractState,
            tournament_id: u64,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) {
            // Open validator doesn't track entries
            // This is a no-op
        }
    }
}
