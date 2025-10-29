use starknet::ContractAddress;

#[starknet::interface]
pub trait IEntryValidatorMock<TState> {
    fn get_tournament_erc721_address(self: @TState, tournament_id: u64) -> ContractAddress;
}

#[starknet::contract]
pub mod entry_validator_mock {
    use budokan_extensions::entry_validator::entry_validator::EntryValidatorComponent;
    use budokan_extensions::entry_validator::entry_validator::EntryValidatorComponent::EntryValidator;
    use core::num::traits::Zero;
    use openzeppelin_introspection::src5::SRC5Component;
    use openzeppelin_token::erc721::interface::{IERC721Dispatcher, IERC721DispatcherTrait};
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
        tournament_erc721_address: Map<u64, ContractAddress>,
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
            let erc721_address = self.tournament_erc721_address.read(tournament_id);

            // Check if ERC721 address is set for this tournament
            if erc721_address.is_zero() {
                return false;
            }

            let erc721 = IERC721Dispatcher { contract_address: erc721_address };

            // Check if the player owns at least one token
            let balance = erc721.balance_of(player_address);
            balance > 0
        }

        fn entries_left(
            self: @ContractState,
            tournament_id: u64,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) -> Option<u8> {
            // For this mock, we assume unlimited entries
            Option::None
        }

        fn add_config(
            ref self: ContractState, tournament_id: u64, entry_limit: u8, config: Span<felt252>,
        ) {
            // Extract ERC721 address from config (first element)
            let erc721_address: ContractAddress = (*config.at(0)).try_into().unwrap();
            self.tournament_erc721_address.write(tournament_id, erc721_address);
        }

        fn add_entry(
            ref self: ContractState,
            tournament_id: u64,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) { // No specific action needed for this mock on add_entry
        }
    }

    // Public interface implementation
    use super::IEntryValidatorMock;
    #[abi(embed_v0)]
    impl EntryValidatorMockImpl of IEntryValidatorMock<ContractState> {
        fn get_tournament_erc721_address(
            self: @ContractState, tournament_id: u64,
        ) -> ContractAddress {
            self.tournament_erc721_address.read(tournament_id)
        }
    }
}
