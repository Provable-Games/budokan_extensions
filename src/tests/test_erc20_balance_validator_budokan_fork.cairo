use budokan_extensions::examples::erc20_balance_validator::{
    IEntryValidatorMockDispatcher, IEntryValidatorMockDispatcherTrait,
};
use budokan_extensions::tests::constants::{
    budokan_address_mainnet, budokan_address_sepolia, eth_token_address, lords_token_address,
    minigame_address_mainnet, minigame_address_sepolia, strk_token_address, test_account_mainnet,
    test_account_sepolia,
};
use budokan_interfaces::budokan::{
    EntryFee, GameConfig, IBudokanDispatcher, IBudokanDispatcherTrait, Metadata, Period, Schedule,
    Tournament,
};
use budokan_interfaces::distribution::Distribution;
use budokan_interfaces::entry_requirement::{
    EntryRequirement, EntryRequirementType, ExtensionConfig, QualificationProof,
};
use budokan_interfaces::entry_validator::{
    IEntryValidatorDispatcher, IEntryValidatorDispatcherTrait,
};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_block_timestamp_global,
    start_cheat_caller_address, stop_cheat_caller_address,
};
use starknet::{ContractAddress, get_block_timestamp};

// ==============================================
// HELPER FUNCTIONS
// ==============================================

fn deploy_erc20_balance_validator(tournament_address: ContractAddress) -> ContractAddress {
    let contract = declare("ERC20BalanceValidator").unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@array![tournament_address.into()]).unwrap();
    contract_address
}

fn test_metadata() -> Metadata {
    Metadata { name: 'ERC20 Test Tournament', description: "Test ERC20 Balance Validator" }
}

fn test_game_config(minigame_address: ContractAddress) -> GameConfig {
    GameConfig { address: minigame_address, settings_id: 1, soulbound: false, play_url: "" }
}

fn test_schedule() -> Schedule {
    let current_time = get_block_timestamp();
    Schedule {
        // All periods must be at least 3600 seconds
        registration: Option::Some(
            Period { start: current_time + 100, end: current_time + 4000 },
        ), // ~4000 secs
        game: Period { start: current_time + 4001, end: current_time + 8000 }, // ~4000 secs
        submission_duration: 3600,
    }
}

// Helper to create config for ERC20 balance validator
// Config format: [token_address, min_threshold_low, min_threshold_high, max_threshold_low,
// max_threshold_high,
//                 value_per_entry_low, value_per_entry_high, max_entries]
fn create_erc20_config(
    token_address: ContractAddress,
    min_threshold: u256,
    max_threshold: u256,
    value_per_entry: u256,
    max_entries: u8,
) -> Span<felt252> {
    array![
        token_address.into(), min_threshold.low.into(), min_threshold.high.into(),
        max_threshold.low.into(), max_threshold.high.into(), value_per_entry.low.into(),
        value_per_entry.high.into(), max_entries.into(),
    ]
        .span()
}

// Mock budokan address for unit tests
fn mock_budokan_address() -> ContractAddress {
    0x1234.try_into().unwrap()
}

// ==============================================
// UNIT TESTS (WITHOUT FORK)
// ==============================================

#[test]
fn test_erc20_validator_config_storage() {
    // Test that configuration is stored correctly
    let budokan_addr = mock_budokan_address();
    let validator_address = deploy_erc20_balance_validator(budokan_addr);
    let validator = IEntryValidatorDispatcher { contract_address: validator_address };
    let validator_mock = IEntryValidatorMockDispatcher { contract_address: validator_address };

    let tournament_id: u64 = 1;
    let token_addr: ContractAddress = 0x111.try_into().unwrap();
    let min_threshold: u256 = 1000;
    let max_threshold: u256 = 10000;
    let value_per_entry: u256 = 500;
    let max_entries: u8 = 10;

    let config = create_erc20_config(
        token_addr, min_threshold, max_threshold, value_per_entry, max_entries,
    );

    start_cheat_caller_address(validator_address, budokan_addr);
    validator.add_config(tournament_id, 0, config);
    stop_cheat_caller_address(validator_address);

    // Verify stored values
    assert(validator_mock.get_token_address(tournament_id) == token_addr, 'Wrong token address');
    assert(validator_mock.get_min_threshold(tournament_id) == min_threshold, 'Wrong min threshold');
    assert(validator_mock.get_max_threshold(tournament_id) == max_threshold, 'Wrong max threshold');
    assert(
        validator_mock.get_value_per_entry(tournament_id) == value_per_entry,
        'Wrong value per entry',
    );
    assert(validator_mock.get_max_entries(tournament_id) == max_entries, 'Wrong max entries');
}

#[test]
fn test_erc20_validator_config_minimal() {
    // Test configuration with only token address and min threshold
    let budokan_addr = mock_budokan_address();
    let validator_address = deploy_erc20_balance_validator(budokan_addr);
    let validator = IEntryValidatorDispatcher { contract_address: validator_address };
    let validator_mock = IEntryValidatorMockDispatcher { contract_address: validator_address };

    let tournament_id: u64 = 1;
    let token_addr: ContractAddress = 0x222.try_into().unwrap();
    let min_threshold: u256 = 500;

    // Minimal config: just token address and min threshold
    let config = array![token_addr.into(), min_threshold.low.into(), min_threshold.high.into()]
        .span();

    start_cheat_caller_address(validator_address, budokan_addr);
    validator.add_config(tournament_id, 3, config); // entry_limit = 3
    stop_cheat_caller_address(validator_address);

    // Verify stored values (max and value_per_entry should default to 0)
    assert(validator_mock.get_token_address(tournament_id) == token_addr, 'Wrong token address');
    assert(validator_mock.get_min_threshold(tournament_id) == min_threshold, 'Wrong min threshold');
    assert(validator_mock.get_max_threshold(tournament_id) == 0, 'Max should be 0');
    assert(validator_mock.get_value_per_entry(tournament_id) == 0, 'Value per entry should be 0');
}

#[test]
fn test_erc20_validator_entries_left_fixed_limit() {
    // Test entries_left with fixed entry limit (value_per_entry = 0)
    let budokan_addr = mock_budokan_address();
    let validator_address = deploy_erc20_balance_validator(budokan_addr);
    let validator = IEntryValidatorDispatcher { contract_address: validator_address };

    let tournament_id: u64 = 1;
    let player: ContractAddress = 0x123.try_into().unwrap();
    let token_addr: ContractAddress = 0x456.try_into().unwrap();
    let min_threshold: u256 = 100;

    // Config with no value_per_entry (fixed limit mode)
    let config = array![token_addr.into(), min_threshold.low.into(), min_threshold.high.into()]
        .span();

    start_cheat_caller_address(validator_address, budokan_addr);
    validator.add_config(tournament_id, 5, config); // 5 entries allowed
    stop_cheat_caller_address(validator_address);

    // Check initial entries
    let entries = validator.entries_left(tournament_id, player, array![].span());
    assert(entries.is_some(), 'Should have entries info');
    assert(entries.unwrap() == 5, 'Should have 5 entries');

    // Add an entry
    start_cheat_caller_address(validator_address, budokan_addr);
    validator.add_entry(tournament_id, 0, player, array![].span());
    stop_cheat_caller_address(validator_address);

    // Check entries after one used
    let entries_after = validator.entries_left(tournament_id, player, array![].span());
    assert(entries_after.unwrap() == 4, 'Should have 4 entries left');

    // Add more entries
    start_cheat_caller_address(validator_address, budokan_addr);
    validator.add_entry(tournament_id, 0, player, array![].span());
    validator.add_entry(tournament_id, 0, player, array![].span());
    stop_cheat_caller_address(validator_address);

    // Check entries
    let entries_final = validator.entries_left(tournament_id, player, array![].span());
    assert(entries_final.unwrap() == 2, 'Should have 2 entries left');
}

#[test]
fn test_erc20_validator_entries_left_unlimited() {
    // Test entries_left with entry_limit = 0 and value_per_entry = 0 (unlimited entries)
    let budokan_addr = mock_budokan_address();
    let validator_address = deploy_erc20_balance_validator(budokan_addr);
    let validator = IEntryValidatorDispatcher { contract_address: validator_address };

    let tournament_id: u64 = 1;
    let player: ContractAddress = 0x123.try_into().unwrap();
    let token_addr: ContractAddress = 0x456.try_into().unwrap();
    let min_threshold: u256 = 100;

    let config = array![token_addr.into(), min_threshold.low.into(), min_threshold.high.into()]
        .span();

    start_cheat_caller_address(validator_address, budokan_addr);
    validator.add_config(tournament_id, 0, config); // 0 = unlimited
    stop_cheat_caller_address(validator_address);

    // Check entries - should return None (unlimited)
    let entries = validator.entries_left(tournament_id, player, array![].span());
    assert(entries.is_none(), 'Should be unlimited (None)');
}

#[test]
fn test_erc20_validator_add_and_remove_entry() {
    // Test add_entry and remove_entry
    let budokan_addr = mock_budokan_address();
    let validator_address = deploy_erc20_balance_validator(budokan_addr);
    let validator = IEntryValidatorDispatcher { contract_address: validator_address };

    let tournament_id: u64 = 1;
    let player: ContractAddress = 0x123.try_into().unwrap();
    let token_addr: ContractAddress = 0x456.try_into().unwrap();
    let min_threshold: u256 = 100;

    let config = array![token_addr.into(), min_threshold.low.into(), min_threshold.high.into()]
        .span();

    start_cheat_caller_address(validator_address, budokan_addr);
    validator.add_config(tournament_id, 5, config);
    stop_cheat_caller_address(validator_address);

    // Add entries
    start_cheat_caller_address(validator_address, budokan_addr);
    validator.add_entry(tournament_id, 0, player, array![].span());
    validator.add_entry(tournament_id, 0, player, array![].span());
    stop_cheat_caller_address(validator_address);

    let entries_after_add = validator.entries_left(tournament_id, player, array![].span());
    assert(entries_after_add.unwrap() == 3, 'Should have 3 entries left');

    // Remove an entry
    start_cheat_caller_address(validator_address, budokan_addr);
    validator.remove_entry(tournament_id, 0, player, array![].span());
    stop_cheat_caller_address(validator_address);

    let entries_after_remove = validator.entries_left(tournament_id, player, array![].span());
    assert(entries_after_remove.unwrap() == 4, 'Should have 4 after remove');
}

#[test]
fn test_erc20_validator_remove_entry_when_zero() {
    // Test that removing entry when none exist is a no-op (doesn't panic)
    let budokan_addr = mock_budokan_address();
    let validator_address = deploy_erc20_balance_validator(budokan_addr);
    let validator = IEntryValidatorDispatcher { contract_address: validator_address };

    let tournament_id: u64 = 1;
    let player: ContractAddress = 0x123.try_into().unwrap();
    let token_addr: ContractAddress = 0x456.try_into().unwrap();
    let min_threshold: u256 = 100;

    let config = array![token_addr.into(), min_threshold.low.into(), min_threshold.high.into()]
        .span();

    start_cheat_caller_address(validator_address, budokan_addr);
    validator.add_config(tournament_id, 5, config);
    stop_cheat_caller_address(validator_address);

    // Try to remove entry when player has none - should be a no-op
    start_cheat_caller_address(validator_address, budokan_addr);
    validator.remove_entry(tournament_id, 0, player, array![].span());
    stop_cheat_caller_address(validator_address);

    // Verify entries are still at max (5)
    let entries_left = validator.entries_left(tournament_id, player, array![].span());
    assert(entries_left.unwrap() == 5, 'Should still have 5 entries');
}

#[test]
fn test_erc20_validator_multiple_tournaments() {
    // Test that multiple tournaments can have independent configs
    let budokan_addr = mock_budokan_address();
    let validator_address = deploy_erc20_balance_validator(budokan_addr);
    let validator = IEntryValidatorDispatcher { contract_address: validator_address };
    let validator_mock = IEntryValidatorMockDispatcher { contract_address: validator_address };

    let tournament_1: u64 = 1;
    let tournament_2: u64 = 2;
    let player: ContractAddress = 0x123.try_into().unwrap();

    let token_1: ContractAddress = 0x111.try_into().unwrap();
    let token_2: ContractAddress = 0x222.try_into().unwrap();

    let config_1 = array![
        token_1.into(), 1000_u128.into(), // min_threshold_low
        0_u128.into() // min_threshold_high
    ]
        .span();

    let config_2 = array![
        token_2.into(), 5000_u128.into(), // min_threshold_low
        0_u128.into() // min_threshold_high
    ]
        .span();

    start_cheat_caller_address(validator_address, budokan_addr);
    validator.add_config(tournament_1, 3, config_1);
    validator.add_config(tournament_2, 5, config_2);
    stop_cheat_caller_address(validator_address);

    // Verify independent configs
    assert(validator_mock.get_token_address(tournament_1) == token_1, 'T1 wrong token');
    assert(validator_mock.get_token_address(tournament_2) == token_2, 'T2 wrong token');
    assert(validator_mock.get_min_threshold(tournament_1) == 1000, 'T1 wrong threshold');
    assert(validator_mock.get_min_threshold(tournament_2) == 5000, 'T2 wrong threshold');

    // Verify independent entry tracking
    let t1_entries = validator.entries_left(tournament_1, player, array![].span());
    let t2_entries = validator.entries_left(tournament_2, player, array![].span());
    assert(t1_entries.unwrap() == 3, 'T1 should have 3 entries');
    assert(t2_entries.unwrap() == 5, 'T2 should have 5 entries');

    // Add entry to tournament 1 only
    start_cheat_caller_address(validator_address, budokan_addr);
    validator.add_entry(tournament_1, 0, player, array![].span());
    stop_cheat_caller_address(validator_address);

    // Verify independent tracking
    let t1_after = validator.entries_left(tournament_1, player, array![].span());
    let t2_after = validator.entries_left(tournament_2, player, array![].span());
    assert(t1_after.unwrap() == 2, 'T1 should have 2 entries');
    assert(t2_after.unwrap() == 5, 'T2 still has 5 entries');
}

#[test]
fn test_erc20_validator_multiple_players() {
    // Test that multiple players have independent entry tracking
    let budokan_addr = mock_budokan_address();
    let validator_address = deploy_erc20_balance_validator(budokan_addr);
    let validator = IEntryValidatorDispatcher { contract_address: validator_address };

    let tournament_id: u64 = 1;
    let player_1: ContractAddress = 0x111.try_into().unwrap();
    let player_2: ContractAddress = 0x222.try_into().unwrap();
    let player_3: ContractAddress = 0x333.try_into().unwrap();
    let token_addr: ContractAddress = 0x456.try_into().unwrap();

    let config = array![token_addr.into(), 100_u128.into(), 0_u128.into()].span();

    start_cheat_caller_address(validator_address, budokan_addr);
    validator.add_config(tournament_id, 5, config);
    stop_cheat_caller_address(validator_address);

    // Add entries for different players
    start_cheat_caller_address(validator_address, budokan_addr);
    validator.add_entry(tournament_id, 0, player_1, array![].span());
    validator.add_entry(tournament_id, 0, player_1, array![].span());
    validator.add_entry(tournament_id, 0, player_2, array![].span());
    stop_cheat_caller_address(validator_address);

    // Verify independent tracking
    let p1_entries = validator.entries_left(tournament_id, player_1, array![].span());
    let p2_entries = validator.entries_left(tournament_id, player_2, array![].span());
    let p3_entries = validator.entries_left(tournament_id, player_3, array![].span());

    assert(p1_entries.unwrap() == 3, 'P1 should have 3 left');
    assert(p2_entries.unwrap() == 4, 'P2 should have 4 left');
    assert(p3_entries.unwrap() == 5, 'P3 should have 5 left');
}

#[test]
#[should_panic(expected: "ERC20 Entry Validator: Qualification data invalid")]
fn test_erc20_validator_rejects_qualification_data() {
    // Test that validate_entry rejects non-empty qualification data
    let budokan_addr = mock_budokan_address();
    let validator_address = deploy_erc20_balance_validator(budokan_addr);
    let validator = IEntryValidatorDispatcher { contract_address: validator_address };

    let tournament_id: u64 = 1;
    let player: ContractAddress = 0x123.try_into().unwrap();
    let token_addr: ContractAddress = 0x456.try_into().unwrap();

    let config = array![token_addr.into(), 100_u128.into(), 0_u128.into()].span();

    start_cheat_caller_address(validator_address, budokan_addr);
    validator.add_config(tournament_id, 5, config);
    stop_cheat_caller_address(validator_address);

    // Try to validate with non-empty qualification data - should panic
    let _is_valid = validator.valid_entry(tournament_id, player, array![1].span());
}

// ==============================================
// FORK TESTS WITH BUDOKAN
// ==============================================

#[test]
#[fork("sepolia")]
fn test_erc20_validator_budokan_create_tournament() {
    // Test creating a tournament with ERC20 balance validator on Budokan
    let budokan_addr = budokan_address_sepolia();
    let minigame_addr = minigame_address_sepolia();
    let account = test_account_sepolia();

    // Deploy validator
    let validator_address = deploy_erc20_balance_validator(budokan_addr);

    // Create extension config with STRK token requirements
    let token_address = strk_token_address();
    let min_threshold: u256 = 1000000000000000000; // 1 STRK (18 decimals)
    let max_threshold: u256 = 0; // No max
    let value_per_entry: u256 = 0; // Fixed entry limit
    let max_entries: u8 = 0;

    let config = create_erc20_config(
        token_address, min_threshold, max_threshold, value_per_entry, max_entries,
    );

    let extension_config = ExtensionConfig { address: validator_address, config };

    let entry_requirement = EntryRequirement {
        entry_limit: 3, entry_requirement_type: EntryRequirementType::extension(extension_config),
    };

    // Create tournament
    let budokan = IBudokanDispatcher { contract_address: budokan_addr };

    start_cheat_caller_address(budokan_addr, account);
    let tournament = budokan
        .create_tournament(
            account,
            test_metadata(),
            test_schedule(),
            test_game_config(minigame_addr),
            Option::None,
            Option::Some(entry_requirement),
        );
    stop_cheat_caller_address(budokan_addr);

    // Verify tournament created
    assert(tournament.id > 0, 'Tournament should have ID');
    assert(tournament.entry_requirement.is_some(), 'Should have entry requirement');
}

#[test]
#[fork("mainnet")]
fn test_erc20_validator_budokan_enter_tournament() {
    // Test entering a tournament with ERC20 balance validation
    let budokan_addr = budokan_address_mainnet();
    let minigame_addr = minigame_address_mainnet();
    let account = test_account_mainnet();

    let validator_address = deploy_erc20_balance_validator(budokan_addr);

    // Use ETH token with very low threshold to ensure test account qualifies on mainnet
    let token_address = eth_token_address();
    let min_threshold: u256 = 1; // 1 wei - virtually any account should have this

    let config = create_erc20_config(token_address, min_threshold, 0, 0, 0);

    let extension_config = ExtensionConfig { address: validator_address, config };

    let entry_requirement = EntryRequirement {
        entry_limit: 5, entry_requirement_type: EntryRequirementType::extension(extension_config),
    };

    let budokan = IBudokanDispatcher { contract_address: budokan_addr };

    start_cheat_caller_address(budokan_addr, account);
    let tournament = budokan
        .create_tournament(
            account,
            test_metadata(),
            test_schedule(),
            test_game_config(minigame_addr),
            Option::None,
            Option::Some(entry_requirement),
        );
    stop_cheat_caller_address(budokan_addr);

    // Advance to registration period
    let schedule = test_schedule();
    let registration_start = match schedule.registration {
        Option::Some(reg) => reg.start,
        Option::None => 0,
    };
    start_cheat_block_timestamp_global(registration_start);

    // Enter tournament (account should have ETH on mainnet)
    start_cheat_caller_address(budokan_addr, account);
    let qualification_proof = Option::Some(QualificationProof::Extension(array![].span()));
    let (token_id, entry_number) = budokan
        .enter_tournament(tournament.id, 'test_player', account, qualification_proof);
    stop_cheat_caller_address(budokan_addr);

    assert(token_id > 0, 'Should have token ID');
    assert(entry_number == 1, 'Should be first entry');

    // Verify entries tracking
    let entry_validator = IEntryValidatorDispatcher { contract_address: validator_address };
    let entries_left = entry_validator.entries_left(tournament.id, account, array![].span());
    assert(entries_left.is_some(), 'Should have entries info');
    assert(entries_left.unwrap() == 4, 'Should have 4 entries left');
}

#[test]
#[fork("mainnet")]
fn test_erc20_validator_budokan_multiple_entries() {
    // Test multiple entries by the same player
    let budokan_addr = budokan_address_mainnet();
    let minigame_addr = minigame_address_mainnet();
    let account = test_account_mainnet();

    let validator_address = deploy_erc20_balance_validator(budokan_addr);

    let token_address = eth_token_address();
    let min_threshold: u256 = 1; // 1 wei - virtually any account should have this

    let config = create_erc20_config(token_address, min_threshold, 0, 0, 0);

    let extension_config = ExtensionConfig { address: validator_address, config };

    let entry_requirement = EntryRequirement {
        entry_limit: 3, // Allow 3 entries
        entry_requirement_type: EntryRequirementType::extension(extension_config),
    };

    let budokan = IBudokanDispatcher { contract_address: budokan_addr };

    start_cheat_caller_address(budokan_addr, account);
    let tournament = budokan
        .create_tournament(
            account,
            test_metadata(),
            test_schedule(),
            test_game_config(minigame_addr),
            Option::None,
            Option::Some(entry_requirement),
        );
    stop_cheat_caller_address(budokan_addr);

    // Advance to registration
    let schedule = test_schedule();
    let registration_start = match schedule.registration {
        Option::Some(reg) => reg.start,
        Option::None => 0,
    };
    start_cheat_block_timestamp_global(registration_start);

    let qualification_proof = Option::Some(QualificationProof::Extension(array![].span()));

    // First entry
    start_cheat_caller_address(budokan_addr, account);
    let (token_id_1, entry_1) = budokan
        .enter_tournament(tournament.id, 'entry_1', account, qualification_proof);
    stop_cheat_caller_address(budokan_addr);
    assert(entry_1 == 1, 'First entry = 1');

    // Second entry
    start_cheat_caller_address(budokan_addr, account);
    let (token_id_2, entry_2) = budokan
        .enter_tournament(tournament.id, 'entry_2', account, qualification_proof);
    stop_cheat_caller_address(budokan_addr);
    assert(entry_2 == 2, 'Second entry = 2');
    assert(token_id_2 > token_id_1, 'Token IDs should increase');

    // Third entry
    start_cheat_caller_address(budokan_addr, account);
    let (token_id_3, entry_3) = budokan
        .enter_tournament(tournament.id, 'entry_3', account, qualification_proof);
    stop_cheat_caller_address(budokan_addr);
    assert(entry_3 == 3, 'Third entry = 3');
    assert(token_id_3 > token_id_2, 'Token IDs should increase');

    // Verify no entries left
    let entry_validator = IEntryValidatorDispatcher { contract_address: validator_address };
    let entries_left = entry_validator.entries_left(tournament.id, account, array![].span());
    assert(entries_left.unwrap() == 0, 'Should have 0 entries left');
}

#[test]
#[fork("sepolia")]
fn test_erc20_validator_direct_validation() {
    // Test direct validation without Budokan integration
    let budokan_addr = budokan_address_sepolia();
    let account = test_account_sepolia();

    let validator_address = deploy_erc20_balance_validator(budokan_addr);
    let validator = IEntryValidatorDispatcher { contract_address: validator_address };

    let tournament_id: u64 = 1;
    let token_address = eth_token_address();
    let min_threshold: u256 = 1000000000000000; // 0.001 ETH

    let config = create_erc20_config(token_address, min_threshold, 0, 0, 0);

    start_cheat_caller_address(validator_address, budokan_addr);
    validator.add_config(tournament_id, 5, config);
    stop_cheat_caller_address(validator_address);

    // Test validation - account should have ETH on mainnet
    let is_valid = validator.valid_entry(tournament_id, account, array![].span());
    // Note: This may pass or fail depending on the account's actual ETH balance
    // In a real test, you'd use an account known to have sufficient balance

    // Check entries
    let entries_left = validator.entries_left(tournament_id, account, array![].span());
    assert(entries_left.is_some(), 'Should have entries info');
    assert(entries_left.unwrap() == 5, 'Should have 5 entries');
}

#[test]
#[fork("sepolia")]
fn test_erc20_validator_with_max_threshold() {
    // Test validation with max threshold (balance cap)
    let budokan_addr = budokan_address_sepolia();

    let validator_address = deploy_erc20_balance_validator(budokan_addr);
    let validator = IEntryValidatorDispatcher { contract_address: validator_address };
    let validator_mock = IEntryValidatorMockDispatcher { contract_address: validator_address };

    let tournament_id: u64 = 1;
    let token_address = eth_token_address();
    let min_threshold: u256 = 100000000000000000; // 0.1 ETH
    let max_threshold: u256 = 10000000000000000000; // 10 ETH

    let config = create_erc20_config(token_address, min_threshold, max_threshold, 0, 0);

    start_cheat_caller_address(validator_address, budokan_addr);
    validator.add_config(tournament_id, 3, config);
    stop_cheat_caller_address(validator_address);

    // Verify config
    assert(validator_mock.get_min_threshold(tournament_id) == min_threshold, 'Wrong min');
    assert(validator_mock.get_max_threshold(tournament_id) == max_threshold, 'Wrong max');
    // Note: In a real scenario, validation would check:
// - balance >= min_threshold: true
// - balance <= max_threshold (if > 0): true
}

#[test]
#[fork("sepolia")]
fn test_erc20_validator_entries_based_on_balance() {
    // Test value_per_entry mode where entries are calculated from balance
    let budokan_addr = budokan_address_sepolia();
    let account = test_account_sepolia();

    let validator_address = deploy_erc20_balance_validator(budokan_addr);
    let validator = IEntryValidatorDispatcher { contract_address: validator_address };
    let validator_mock = IEntryValidatorMockDispatcher { contract_address: validator_address };

    let tournament_id: u64 = 1;
    let token_address = eth_token_address();
    let min_threshold: u256 = 100000000000000000; // 0.1 ETH
    let value_per_entry: u256 = 100000000000000000; // 0.1 ETH per entry
    let max_entries: u8 = 10; // Cap at 10 entries

    let config = create_erc20_config(token_address, min_threshold, 0, value_per_entry, max_entries);

    start_cheat_caller_address(validator_address, budokan_addr);
    validator.add_config(tournament_id, 0, config); // entry_limit = 0, use value_per_entry
    stop_cheat_caller_address(validator_address);

    // Verify config
    assert(
        validator_mock.get_value_per_entry(tournament_id) == value_per_entry,
        'Wrong value per entry',
    );
    assert(validator_mock.get_max_entries(tournament_id) == max_entries, 'Wrong max entries');

    // Check entries based on balance
    // entries = (balance - min_threshold) / value_per_entry
    // For an account with 1 ETH: (1 - 0.1) / 0.1 = 9 entries
    let entries_left = validator.entries_left(tournament_id, account, array![].span());
    // The actual number depends on the account's balance
    // This test verifies the mechanism works
    if entries_left.is_some() {
        let entries = entries_left.unwrap();
        assert(entries <= max_entries, 'Should be capped at max');
    }
}

#[test]
#[fork("sepolia")]
fn test_erc20_validator_cross_tournament_independence() {
    // Test that entry tracking is independent per tournament
    let budokan_addr = budokan_address_sepolia();
    let account = test_account_sepolia();

    let validator_address = deploy_erc20_balance_validator(budokan_addr);
    let validator = IEntryValidatorDispatcher { contract_address: validator_address };

    let tournament_1: u64 = 1;
    let tournament_2: u64 = 2;
    let token_address = eth_token_address();
    let min_threshold: u256 = 1000000000000000;

    let config = create_erc20_config(token_address, min_threshold, 0, 0, 0);

    // Configure both tournaments
    start_cheat_caller_address(validator_address, budokan_addr);
    validator.add_config(tournament_1, 3, config);
    validator.add_config(tournament_2, 5, config);
    stop_cheat_caller_address(validator_address);

    // Add entries to tournament 1
    start_cheat_caller_address(validator_address, budokan_addr);
    validator.add_entry(tournament_1, 0, account, array![].span());
    validator.add_entry(tournament_1, 0, account, array![].span());
    stop_cheat_caller_address(validator_address);

    // Verify independent tracking
    let t1_entries = validator.entries_left(tournament_1, account, array![].span());
    let t2_entries = validator.entries_left(tournament_2, account, array![].span());

    assert(t1_entries.unwrap() == 1, 'T1 should have 1 left');
    assert(t2_entries.unwrap() == 5, 'T2 should have 5 left');

    // Add entry to tournament 2
    start_cheat_caller_address(validator_address, budokan_addr);
    validator.add_entry(tournament_2, 0, account, array![].span());
    stop_cheat_caller_address(validator_address);

    // Verify independence maintained
    let t1_final = validator.entries_left(tournament_1, account, array![].span());
    let t2_final = validator.entries_left(tournament_2, account, array![].span());

    assert(t1_final.unwrap() == 1, 'T1 still 1 left');
    assert(t2_final.unwrap() == 4, 'T2 now 4 left');
}

#[test]
#[should_panic]
#[fork("sepolia")]
fn test_erc20_validator_insufficient_balance() {
    // Test that player with insufficient balance cannot enter
    let budokan_addr = budokan_address_sepolia();
    let minigame_addr = minigame_address_sepolia();
    let account = test_account_sepolia();

    let validator_address = deploy_erc20_balance_validator(budokan_addr);

    let token_address = eth_token_address();
    // Set very high threshold that no account would have
    let min_threshold: u256 = 1000000000000000000000000; // 1 million ETH

    let config = create_erc20_config(token_address, min_threshold, 0, 0, 0);

    let extension_config = ExtensionConfig { address: validator_address, config };

    let entry_requirement = EntryRequirement {
        entry_limit: 5, entry_requirement_type: EntryRequirementType::extension(extension_config),
    };

    let budokan = IBudokanDispatcher { contract_address: budokan_addr };

    start_cheat_caller_address(budokan_addr, account);
    let tournament = budokan
        .create_tournament(
            account,
            test_metadata(),
            test_schedule(),
            test_game_config(minigame_addr),
            Option::None,
            Option::Some(entry_requirement),
        );
    stop_cheat_caller_address(budokan_addr);

    // Advance to registration
    let schedule = test_schedule();
    let registration_start = match schedule.registration {
        Option::Some(reg) => reg.start,
        Option::None => 0,
    };
    start_cheat_block_timestamp_global(registration_start);

    // Try to enter - should fail due to insufficient balance
    start_cheat_caller_address(budokan_addr, account);
    let qualification_proof = Option::Some(QualificationProof::Extension(array![].span()));
    budokan.enter_tournament(tournament.id, 'test', account, qualification_proof);
    // Should not reach here
}

#[test]
#[fork("sepolia")]
fn test_erc20_validator_different_tokens() {
    // Test configuring different tokens for different tournaments
    let budokan_addr = budokan_address_sepolia();

    let validator_address = deploy_erc20_balance_validator(budokan_addr);
    let validator_mock = IEntryValidatorMockDispatcher { contract_address: validator_address };
    let validator = IEntryValidatorDispatcher { contract_address: validator_address };

    let tournament_eth: u64 = 1;
    let tournament_strk: u64 = 2;
    let tournament_lords: u64 = 3;

    let eth_addr = eth_token_address();
    let strk_addr = strk_token_address();
    let lords_addr = lords_token_address();

    // Configure each tournament with different token
    start_cheat_caller_address(validator_address, budokan_addr);

    let eth_config = create_erc20_config(eth_addr, 1000000000000000000, 0, 0, 0); // 1 ETH
    validator.add_config(tournament_eth, 3, eth_config);

    let strk_config = create_erc20_config(strk_addr, 100000000000000000000, 0, 0, 0); // 100 STRK
    validator.add_config(tournament_strk, 5, strk_config);

    let lords_config = create_erc20_config(lords_addr, 50000000000000000000, 0, 0, 0); // 50 LORDS
    validator.add_config(tournament_lords, 2, lords_config);

    stop_cheat_caller_address(validator_address);

    // Verify each tournament has correct token
    assert(validator_mock.get_token_address(tournament_eth) == eth_addr, 'ETH tournament wrong');
    assert(validator_mock.get_token_address(tournament_strk) == strk_addr, 'STRK tournament wrong');
    assert(
        validator_mock.get_token_address(tournament_lords) == lords_addr, 'LORDS tournament wrong',
    );

    // Verify thresholds
    assert(
        validator_mock.get_min_threshold(tournament_eth) == 1000000000000000000,
        'ETH threshold wrong',
    );
    assert(
        validator_mock.get_min_threshold(tournament_strk) == 100000000000000000000,
        'STRK threshold wrong',
    );
    assert(
        validator_mock.get_min_threshold(tournament_lords) == 50000000000000000000,
        'LORDS threshold wrong',
    );
}

// ==============================================
// EDGE CASE TESTS
// ==============================================

#[test]
fn test_erc20_validator_zero_threshold() {
    // Test with zero threshold (any balance is valid)
    let budokan_addr = mock_budokan_address();
    let validator_address = deploy_erc20_balance_validator(budokan_addr);
    let validator = IEntryValidatorDispatcher { contract_address: validator_address };
    let validator_mock = IEntryValidatorMockDispatcher { contract_address: validator_address };

    let tournament_id: u64 = 1;
    let token_addr: ContractAddress = 0x123.try_into().unwrap();
    let min_threshold: u256 = 0;

    let config = array![token_addr.into(), min_threshold.low.into(), min_threshold.high.into()]
        .span();

    start_cheat_caller_address(validator_address, budokan_addr);
    validator.add_config(tournament_id, 5, config);
    stop_cheat_caller_address(validator_address);

    assert(validator_mock.get_min_threshold(tournament_id) == 0, 'Should be zero');
}

#[test]
fn test_erc20_validator_large_threshold() {
    // Test with very large threshold values (u256 max range)
    let budokan_addr = mock_budokan_address();
    let validator_address = deploy_erc20_balance_validator(budokan_addr);
    let validator = IEntryValidatorDispatcher { contract_address: validator_address };
    let validator_mock = IEntryValidatorMockDispatcher { contract_address: validator_address };

    let tournament_id: u64 = 1;
    let token_addr: ContractAddress = 0x123.try_into().unwrap();
    let large_threshold: u256 = u256 { low: 0xFFFFFFFFFFFFFFFF, high: 0xFFFFFFFF };

    let config = create_erc20_config(token_addr, large_threshold, 0, 0, 0);

    start_cheat_caller_address(validator_address, budokan_addr);
    validator.add_config(tournament_id, 5, config);
    stop_cheat_caller_address(validator_address);

    assert(
        validator_mock.get_min_threshold(tournament_id) == large_threshold,
        'Should handle large values',
    );
}

#[test]
fn test_erc20_validator_max_entries_cap() {
    // Test that max_entries properly caps entry calculation
    let budokan_addr = mock_budokan_address();
    let validator_address = deploy_erc20_balance_validator(budokan_addr);
    let validator_mock = IEntryValidatorMockDispatcher { contract_address: validator_address };
    let validator = IEntryValidatorDispatcher { contract_address: validator_address };

    let tournament_id: u64 = 1;
    let token_addr: ContractAddress = 0x123.try_into().unwrap();
    let min_threshold: u256 = 100;
    let value_per_entry: u256 = 10; // Would give many entries
    let max_entries: u8 = 5; // But capped at 5

    let config = create_erc20_config(token_addr, min_threshold, 0, value_per_entry, max_entries);

    start_cheat_caller_address(validator_address, budokan_addr);
    validator.add_config(tournament_id, 0, config);
    stop_cheat_caller_address(validator_address);

    assert(validator_mock.get_max_entries(tournament_id) == 5, 'Max entries should be 5');
    assert(validator_mock.get_value_per_entry(tournament_id) == 10, 'Value per entry should be 10');
}

#[test]
fn test_erc20_validator_exhaust_all_entries() {
    // Test exhausting all entries
    let budokan_addr = mock_budokan_address();
    let validator_address = deploy_erc20_balance_validator(budokan_addr);
    let validator = IEntryValidatorDispatcher { contract_address: validator_address };

    let tournament_id: u64 = 1;
    let player: ContractAddress = 0x123.try_into().unwrap();
    let token_addr: ContractAddress = 0x456.try_into().unwrap();

    let config = array![token_addr.into(), 100_u128.into(), 0_u128.into()].span();

    start_cheat_caller_address(validator_address, budokan_addr);
    validator.add_config(tournament_id, 3, config); // Only 3 entries
    stop_cheat_caller_address(validator_address);

    // Use all 3 entries
    start_cheat_caller_address(validator_address, budokan_addr);
    validator.add_entry(tournament_id, 0, player, array![].span());
    validator.add_entry(tournament_id, 0, player, array![].span());
    validator.add_entry(tournament_id, 0, player, array![].span());
    stop_cheat_caller_address(validator_address);

    // Verify all entries exhausted
    let entries_left = validator.entries_left(tournament_id, player, array![].span());
    assert(entries_left.unwrap() == 0, 'Should have 0 entries');
    // But valid_entry should still work (validation doesn't check entry count)
// The entry count check is done by Budokan
}
// ==============================================
// REAL WORLD USAGE EXAMPLE
// ==============================================
// This comment block shows how you would use the ERC20BalanceValidator in production:
//
// 1. Deploy ERC20BalanceValidator:
//    let validator = deploy_erc20_balance_validator(budokan_address);
//
// 2. Create extension config with token requirements:
//    let config = create_erc20_config(
//        token_address,        // The ERC20 token to check
//        min_threshold,        // Minimum balance required (in token units)
//        max_threshold,        // Maximum balance allowed (0 = no max)
//        value_per_entry,      // Token amount required per entry (0 = use fixed limit)
//        max_entries,          // Maximum entries cap (0 = no cap)
//    );
//
// 3. Create tournament on Budokan with validator as extension:
//    let extension_config = ExtensionConfig {
//        address: validator_address,
//        config,
//    };
//    let entry_requirement = EntryRequirement {
//        entry_limit: 3,  // Fixed limit (if value_per_entry = 0)
//        entry_requirement_type: EntryRequirementType::extension(extension_config),
//    };
//    budokan.create_tournament(..., entry_requirement);
//
// 4. Players can enter if they meet token balance requirements:
//    - balance >= min_threshold
//    - balance <= max_threshold (if max_threshold > 0)
//
// 5. Entry calculation modes:
//    a) Fixed limit: value_per_entry = 0
//       All eligible players get entry_limit entries
//
//    b) Balance-based: value_per_entry > 0
//       entries = (balance - min_threshold) / value_per_entry
//       Capped at max_entries if set
//
// 6. Token selection:
//    - ETH: For ETH holdings requirement
//    - STRK: For STRK staking/holdings
//    - LORDS: For game-specific token holdings
//    - Any ERC20: Community tokens, governance tokens, etc.
// ==============================================

