use starknet::{ContractAddress};
use budokan_extensions::entry_validator::entry_validator::EntryValidatorComponent;
use openzeppelin_token::erc721::interface::{IERC721Dispatcher, IERC721DispatcherTrait};
use openzeppelin_introspection::src5::SRC5Component;


#[starknet::interface]
pub trait IEntryValidatorMock<TState> {
    fn governor_address(self: @TState) -> ContractAddress;
}

#[starknet::contract]
pub mod entry_validator_mock {
    use starknet::ContractAddress;
    use budokan_extensions::entry_validator::entry_validator::EntryValidatorComponent;
    use budokan_extensions::entry_validator::entry_validator::EntryValidatorComponent::EntryValidator;
    use openzeppelin_token::erc721::interface::{IERC721Dispatcher, IERC721DispatcherTrait};
    use openzeppelin_introspection::src5::SRC5Component;
    use openzeppelin_governance::governor::interface::{IGovernorDispatcher, IGovernorDispatcherTrait};

    const ABBOT: ContractAddress = 0x04d0bb0a4c40012384e7c419e6eb3c637b28e8363fb66958b60d90505b9c072f;
    const FDP: ContractAddress = 0x023037703b187f6ff23b883624a0a9f266c9d44671e762048c70100c2f128ab9;

    component!(path: EntryValidatorComponent, storage: entry_validator, event: EntryValidatorEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    #[abi(embed_v0)]
    impl EntryValidatorImpl = EntryValidatorComponent::EntryValidatorImpl<ContractState>;
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

    // Implement the EntryValidator trait for the contract
    impl EntryValidatorImplInternal of EntryValidator<ContractState> {
        fn validate_entry(
            self: @ContractState,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) -> bool {
            let fdp_address = 
            let fdp = IFrontendDataProvider { contract_address: FDP };
            let trove_id: u64 = user_troves.pop_front().unwrap();
            let trove_info: TroveInfo = fdp.get_trove_info(trove_id);

            let mut deposited_survivor_tokens: u128 = Zero::zero();
            let mut deposited_survivor_value: Wad = Zero::zero();
            for trove_asset_info in trove_info.assets {
                if trove_asset_info.shrine_asset_info.address == SURVIVOR {
                    deposited_survivor_value = trove_asset_info.value;
                    deposited_survivor_tokens = trove_asset_info.amount;
                    break;
                }
            }
        }
    }
}