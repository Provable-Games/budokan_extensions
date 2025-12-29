use starknet::ContractAddress;

#[starknet::interface]
pub trait IEntryValidatorMock<TState> {
    fn get_tournament_erc721_address(self: @TState, tournament_id: u64) -> ContractAddress;
}

#[starknet::contract]
pub mod entry_validator_mock {
    use budokan_entry_requirement::entry_validator::EntryValidatorComponent;
    use budokan_entry_requirement::entry_validator::EntryValidatorComponent::EntryValidator;
    use core::num::traits::Zero;
    use openzeppelin_interfaces::erc721::{IERC721Dispatcher, IERC721DispatcherTrait};
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
    fn constructor(ref self: ContractState, budokan_address: ContractAddress) {
        // ERC721 ownership can change, so allow banning (registration_only = false)
        self.entry_validator.initializer(budokan_address, false);
    }

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

        fn should_ban_entry(
            self: @ContractState,
            tournament_id: u64,
            game_token_id: u64,
            current_owner: ContractAddress,
            qualification: Span<felt252>,
        ) -> bool {
            // Ban if player no longer owns the ERC721 token
            let erc721_address = self.tournament_erc721_address.read(tournament_id);
            if erc721_address.is_zero() {
                return false;
            }

            let erc721 = IERC721Dispatcher { contract_address: erc721_address };
            let balance = erc721.balance_of(current_owner);
            balance == 0
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

        fn on_entry_added(
            ref self: ContractState,
            tournament_id: u64,
            game_token_id: u64,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) { // No specific action needed for this mock
        }

        fn on_entry_removed(
            ref self: ContractState,
            tournament_id: u64,
            game_token_id: u64,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) { // No specific action needed for this mock
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
