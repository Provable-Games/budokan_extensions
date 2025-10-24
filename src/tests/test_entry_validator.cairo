use starknet::ContractAddress;
use snforge_std::{declare, ContractClassTrait, DeclareResultTrait};

use budokan_extensions::tests::mocks::erc721_mock::{
    IERC721MockDispatcher, IERC721MockDispatcherTrait,
    IERC721MockPublicDispatcher, IERC721MockPublicDispatcherTrait
};
use budokan_extensions::tests::mocks::entry_validator_mock::{
    IEntryValidatorMockDispatcher, IEntryValidatorMockDispatcherTrait
};
use budokan_extensions::entry_validator::interface::{
    IEntryValidatorDispatcher, IEntryValidatorDispatcherTrait
};

fn deploy_erc721() -> IERC721MockDispatcher {
    let contract = declare("erc721_mock").unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@array![]).unwrap();
    IERC721MockDispatcher { contract_address }
}

fn deploy_entry_validator(erc721_address: ContractAddress) -> ContractAddress {
    let contract = declare("entry_validator_mock").unwrap().contract_class();
    let (contract_address, _) = contract
        .deploy(@array![erc721_address.into()])
        .unwrap();
    contract_address
}

#[test]
fn test_valid_entry_with_token_ownership() {
    // Deploy ERC721 mock
    let erc721 = deploy_erc721();

    // Deploy entry validator with the ERC721 address
    let entry_validator_address = deploy_entry_validator(erc721.contract_address);
    let entry_validator = IEntryValidatorDispatcher { contract_address: entry_validator_address };

    // Create a player address
    let player: ContractAddress = 0x123.try_into().unwrap();

    // Mint a token to the player
    let erc721_public = IERC721MockPublicDispatcher { contract_address: erc721.contract_address };
    erc721_public.mint(player, 1);

    // Verify the player owns the token
    let balance = erc721.balance_of(player);
    assert(balance == 1, 'Player should own 1 token');

    // Test that the player can enter
    let can_enter = entry_validator.valid_entry(player, Option::None);
    assert(can_enter, 'Player with token should enter');
}

#[test]
fn test_invalid_entry_without_token_ownership() {
    // Deploy ERC721 mock
    let erc721 = deploy_erc721();

    // Deploy entry validator with the ERC721 address
    let entry_validator_address = deploy_entry_validator(erc721.contract_address);
    let entry_validator = IEntryValidatorDispatcher { contract_address: entry_validator_address };

    // Create a player address without any tokens
    let player: ContractAddress = 0x456.try_into().unwrap();

    // Verify the player owns no tokens
    let balance = erc721.balance_of(player);
    assert(balance == 0, 'Player should own 0 tokens');

    // Test that the player cannot enter
    let can_enter = entry_validator.valid_entry(player, Option::None);
    assert(!can_enter, 'No token: cannot enter');
}

#[test]
fn test_valid_entry_with_multiple_tokens() {
    // Deploy ERC721 mock
    let erc721 = deploy_erc721();

    // Deploy entry validator with the ERC721 address
    let entry_validator_address = deploy_entry_validator(erc721.contract_address);
    let entry_validator = IEntryValidatorDispatcher { contract_address: entry_validator_address };

    // Create a player address
    let player: ContractAddress = 0x789.try_into().unwrap();

    // Mint multiple tokens to the player
    let erc721_public = IERC721MockPublicDispatcher { contract_address: erc721.contract_address };
    erc721_public.mint(player, 1);
    erc721_public.mint(player, 2);
    erc721_public.mint(player, 3);

    // Verify the player owns multiple tokens
    let balance = erc721.balance_of(player);
    assert(balance == 3, 'Player should own 3 tokens');

    // Test that the player can enter
    let can_enter = entry_validator.valid_entry(player, Option::None);
    assert(can_enter, 'Player with tokens should enter');
}

#[test]
fn test_entry_status_changes_after_transfer() {
    // Deploy ERC721 mock
    let erc721 = deploy_erc721();

    // Deploy entry validator with the ERC721 address
    let entry_validator_address = deploy_entry_validator(erc721.contract_address);
    let entry_validator = IEntryValidatorDispatcher { contract_address: entry_validator_address };

    // Create player addresses
    let player1: ContractAddress = 0xAAA.try_into().unwrap();
    let player2: ContractAddress = 0xBBB.try_into().unwrap();

    // Mint a token to player1
    let erc721_public = IERC721MockPublicDispatcher { contract_address: erc721.contract_address };
    erc721_public.mint(player1, 1);

    // Verify player1 can enter
    let can_enter = entry_validator.valid_entry(player1, Option::None);
    assert(can_enter, 'Player1 should enter initially');

    // Verify player2 cannot enter
    let can_enter = entry_validator.valid_entry(player2, Option::None);
    assert(!can_enter, 'Player2 no token initially');

    // Transfer token from player1 to player2
    snforge_std::start_cheat_caller_address(erc721.contract_address, player1);
    erc721.transfer_from(player1, player2, 1);
    snforge_std::stop_cheat_caller_address(erc721.contract_address);

    // Verify player1 can no longer enter
    let can_enter = entry_validator.valid_entry(player1, Option::None);
    assert(!can_enter, 'Player1 no token after xfer');

    // Verify player2 can now enter
    let can_enter = entry_validator.valid_entry(player2, Option::None);
    assert(can_enter, 'Player2 can enter after xfer');
}

#[test]
fn test_entry_validator_stores_correct_erc721_address() {
    // Deploy ERC721 mock
    let erc721 = deploy_erc721();

    // Deploy entry validator with the ERC721 address
    let entry_validator_address = deploy_entry_validator(erc721.contract_address);
    let entry_validator_mock = IEntryValidatorMockDispatcher { contract_address: entry_validator_address };

    // Verify the entry validator stores the correct ERC721 address
    let stored_address = entry_validator_mock.get_erc721_address();
    assert(stored_address == erc721.contract_address, 'Wrong ERC721 address stored');
}

#[test]
fn test_multiple_players_with_different_ownership() {
    // Deploy ERC721 mock
    let erc721 = deploy_erc721();

    // Deploy entry validator with the ERC721 address
    let entry_validator_address = deploy_entry_validator(erc721.contract_address);
    let entry_validator = IEntryValidatorDispatcher { contract_address: entry_validator_address };

    // Create multiple player addresses
    let player1: ContractAddress = 0x111.try_into().unwrap();
    let player2: ContractAddress = 0x222.try_into().unwrap();
    let player3: ContractAddress = 0x333.try_into().unwrap();

    // Mint tokens to player1 and player3 only
    let erc721_public = IERC721MockPublicDispatcher { contract_address: erc721.contract_address };
    erc721_public.mint(player1, 1);
    erc721_public.mint(player3, 2);

    // Test entry validation for all players
    let can_enter_p1 = entry_validator.valid_entry(player1, Option::None);
    assert(can_enter_p1, 'Player1 should enter');

    let can_enter_p2 = entry_validator.valid_entry(player2, Option::None);
    assert(!can_enter_p2, 'Player2 should not enter');

    let can_enter_p3 = entry_validator.valid_entry(player3, Option::None);
    assert(can_enter_p3, 'Player3 should enter');
}
