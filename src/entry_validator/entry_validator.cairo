//
// Entry Validator Component
//
#[starknet::component]
pub mod EntryValidatorComponent {
    use openzeppelin_introspection::src5::SRC5Component;
    use openzeppelin_introspection::src5::SRC5Component::InternalTrait as SRC5InternalTrait;
    use starknet::ContractAddress;
    use starknet::storage::{
        StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use super::super::interface::{IENTRY_VALIDATOR_ID, IEntryValidator};

    #[storage]
    pub struct Storage {
        budokan_address: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {}

    pub trait EntryValidator<TContractState> {
        fn validate_entry(
            self: @TContractState,
            tournament_id: u64,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) -> bool;
        fn entries_left(
            self: @TContractState,
            tournament_id: u64,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) -> Option<u8>;
        fn add_config(
            ref self: TContractState, tournament_id: u64, entry_limit: u8, config: Span<felt252>,
        );
        fn add_entry(
            ref self: TContractState,
            tournament_id: u64,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        );
    }

    #[embeddable_as(EntryValidatorImpl)]
    pub impl EntryValidatorImplGeneric<
        TContractState,
        +HasComponent<TContractState>,
        impl Validator: EntryValidator<TContractState>,
        impl SRC5: SRC5Component::HasComponent<TContractState>,
        +Drop<TContractState>,
    > of IEntryValidator<ComponentState<TContractState>> {
        fn valid_entry(
            self: @ComponentState<TContractState>,
            tournament_id: u64,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) -> bool {
            let state = self.get_contract();
            Validator::validate_entry(state, tournament_id, player_address, qualification)
        }

        fn entries_left(
            self: @ComponentState<TContractState>,
            tournament_id: u64,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) -> Option<u8> {
            let state = self.get_contract();
            Validator::entries_left(state, tournament_id, player_address, qualification)
        }

        fn add_config(
            ref self: ComponentState<TContractState>,
            tournament_id: u64,
            entry_limit: u8,
            config: Span<felt252>,
        ) {
            self.assert_only_budokan();
            let mut state = self.get_contract_mut();
            Validator::add_config(ref state, tournament_id, entry_limit, config)
        }

        fn add_entry(
            ref self: ComponentState<TContractState>,
            tournament_id: u64,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) {
            self.assert_only_budokan();
            let mut state = self.get_contract_mut();
            Validator::add_entry(ref state, tournament_id, player_address, qualification)
        }
    }

    #[generate_trait]
    pub impl InternalImpl<
        TContractState,
        +HasComponent<TContractState>,
        impl SRC5: SRC5Component::HasComponent<TContractState>,
        +Drop<TContractState>,
    > of InternalTrait<TContractState> {
        fn initializer(ref self: ComponentState<TContractState>, budokan_address: ContractAddress) {
            self.budokan_address.write(budokan_address);
            self.register_entry_validator_interface();
        }

        fn register_entry_validator_interface(ref self: ComponentState<TContractState>) {
            let mut src5_component = get_dep_component_mut!(ref self, SRC5);
            src5_component.register_interface(IENTRY_VALIDATOR_ID);
        }

        fn assert_only_budokan(
            self: @ComponentState<TContractState>
        ) {
            let caller = starknet::get_caller_address();
            let budokan_address = self.budokan_address.read();
            assert!(
                caller == budokan_address,
                "Entry Validator: Only Budokan can call this function"
            );
        }
    }
}
