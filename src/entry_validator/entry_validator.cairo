//
// Entry Validator Component
//
#[starknet::component]
pub mod EntryValidatorComponent {
    use super::super::interface::{IEntryValidator, IENTRY_VALIDATOR_ID};
    use starknet::ContractAddress;

    use openzeppelin_introspection::src5::SRC5Component;
    use openzeppelin_introspection::src5::SRC5Component::InternalTrait as SRC5InternalTrait;

    #[storage]
    pub struct Storage {}

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {}

    pub trait EntryValidator<TContractState> {
        fn validate_entry(
            self: @TContractState,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) -> bool;
    }

    #[embeddable_as(EntryValidatorImpl)]
    pub impl EntryValidatorImplGeneric<
        TContractState,
        +HasComponent<TContractState>,
        impl Validator: EntryValidator<TContractState>,
        +Drop<TContractState>,
    > of IEntryValidator<ComponentState<TContractState>> {
        fn valid_entry(
            self: @ComponentState<TContractState>, player_address: ContractAddress, qualification: Span<felt252>
        ) -> bool {
            let state = self.get_contract();
            Validator::validate_entry(state, player_address, qualification)
        }
    }

    #[generate_trait]
    pub impl InternalImpl<
        TContractState,
        +HasComponent<TContractState>,
        impl SRC5: SRC5Component::HasComponent<TContractState>,
        +Drop<TContractState>,
    > of InternalTrait<TContractState> {
        fn initializer(ref self: ComponentState<TContractState>) {
            self.register_entry_validator_interface();
        }

        fn register_entry_validator_interface(ref self: ComponentState<TContractState>) {
            let mut src5_component = get_dep_component_mut!(ref self, SRC5);
            src5_component.register_interface(IENTRY_VALIDATOR_ID);
        }
    }
}
