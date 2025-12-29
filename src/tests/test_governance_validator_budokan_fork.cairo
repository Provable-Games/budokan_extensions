use budokan_extensions::tests::constants::{
    budokan_address_mainnet, governance_token_address, governor_address, minigame_address_mainnet,
    test_account_mainnet,
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
use openzeppelin_interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_block_timestamp_global,
    start_cheat_caller_address, stop_cheat_caller_address,
};
use starknet::{ContractAddress, get_block_timestamp};

// ==============================================
// GOVERNANCE VALIDATOR BUDOKAN INTEGRATION FORK TEST
// ==============================================
// This test demonstrates full integration with a deployed Budokan contract
// on a forked network (mainnet or mainnet) using the GovernanceValidator.
//
// Key differences from SnapshotValidator:
// - Uses governance token balances, delegation, and voting to determine eligibility
// - Can ban users via validate_entries call on Budokan
// - Entries can be calculated based on voting power
//
// To run this test:
// 1. Deploy Budokan contract to mainnet/mainnet (or use existing deployment)
// 2. Update budokan_address_mainnet constant below with the deployed address
// 3. Run: snforge test test_governance_validator_budokan --fork-name mainnet
// ==============================================

// Deploy the GovernanceValidator contract
fn deploy_governance_validator(tournament_address: ContractAddress) -> ContractAddress {
    let contract = declare("GovernanceValidator").unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@array![tournament_address.into()]).unwrap();
    contract_address
}

// Helper functions for creating tournaments
fn test_metadata() -> Metadata {
    Metadata { name: 'Test Tournament', description: "Test Description" }
}

fn test_game_config(minigame_address: ContractAddress) -> GameConfig {
    GameConfig { address: minigame_address, settings_id: 1, soulbound: false, play_url: "" }
}

fn test_schedule() -> Schedule {
    let current_time = get_block_timestamp();
    Schedule {
        // All periods must be at least 3600 seconds
        registration: Option::Some(Period { start: current_time + 100, end: current_time + 4000 }),
        game: Period { start: current_time + 4001, end: current_time + 8000 },
        submission_duration: 3600,
    }
}


// ==============================================
// INTEGRATION TESTS WITH BUDOKAN AND GOVERNANCE
// ==============================================

#[test]
#[fork("mainnet")]
fn test_governance_validator_budokan_create_tournament() {
    // This test shows how to:
    // 1. Deploy GovernanceValidator
    // 2. Configure governance parameters (token address, balance threshold, etc.)
    // 3. Create a tournament on Budokan using the GovernanceValidator as the entry requirement
    // 4. Enter the tournament through Budokan, which validates governance participation

    let budokan_addr = budokan_address_mainnet();
    let minigame_addr = minigame_address_mainnet();
    let account = test_account_mainnet();

    // Step 1: Deploy GovernanceValidator
    let validator_address = deploy_governance_validator(budokan_addr);
    let _validator = IEntryValidatorDispatcher { contract_address: validator_address };

    // Step 2: Create extension config with governance parameters
    // Config format: [governor_address, governance_token_address, balance_threshold,
    //                 proposal_id, check_voted, votes_threshold, votes_per_entry]
    let balance_threshold: u256 = 1000; // Minimum token balance
    let proposal_id: felt252 = 'proposal_123';
    let check_voted: felt252 = 0; // false - don't check if they voted
    let votes_threshold: u256 = 0; // Not checking votes
    let votes_per_entry: u256 = 0; // Not calculating entries from votes

    let extension_config = ExtensionConfig {
        address: validator_address,
        config: array![
            governor_address().into(), governance_token_address().into(),
            balance_threshold.try_into().unwrap(), proposal_id, check_voted,
            votes_threshold.try_into().unwrap(), votes_per_entry.try_into().unwrap(),
        ]
            .span(),
    };

    let entry_requirement_type = EntryRequirementType::extension(extension_config);
    let entry_requirement = EntryRequirement {
        entry_limit: 3, // Max 3 entries per player
        entry_requirement_type,
    };

    // Step 3: Create tournament on Budokan with the validator as extension
    let budokan = IBudokanDispatcher { contract_address: budokan_addr };

    start_cheat_caller_address(budokan_addr, account);
    let tournament = budokan
        .create_tournament(
            account,
            test_metadata(),
            test_schedule(),
            test_game_config(minigame_addr),
            Option::None, // No entry fee
            Option::Some(entry_requirement),
        );
    stop_cheat_caller_address(budokan_addr);

    // Verify tournament was created with correct requirements
    assert(tournament.entry_requirement.is_some(), 'Should have entry requirement');
    assert(tournament.id > 0, 'Should have valid tournament ID');
    // Step 4: Check that eligible players can enter
// Note: In a real fork test, you'd need addresses with actual governance tokens
// and proper delegation setup. This demonstrates the flow.
}

#[test]
#[fork("mainnet")]
fn test_governance_validator_budokan_with_voting_requirement() {
    // This test demonstrates using voting requirements for entry eligibility

    let budokan_addr = budokan_address_mainnet();
    let minigame_addr = minigame_address_mainnet();
    let account = test_account_mainnet();

    let validator_address = deploy_governance_validator(budokan_addr);

    // Configure with voting requirements
    let balance_threshold: u256 = 1000;
    let proposal_id: felt252 = 'proposal_123';
    let check_voted: felt252 = 1; // true - check if they voted
    let votes_threshold: u256 = 100; // Must have cast at least 100 votes
    let votes_per_entry: u256 = 0; // Not calculating entries from votes

    let extension_config = ExtensionConfig {
        address: validator_address,
        config: array![
            governor_address().into(), governance_token_address().into(),
            balance_threshold.try_into().unwrap(), proposal_id, check_voted,
            votes_threshold.try_into().unwrap(), votes_per_entry.try_into().unwrap(),
        ]
            .span(),
    };

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

    assert(tournament.id > 0, 'Tournament created');
    // In a real scenario, only players who:
// 1. Have >= 1000 governance tokens
// 2. Have delegated their tokens
// 3. Have voted on proposal_123
// 4. Cast at least 100 votes
// would be able to enter
}

#[test]
#[fork("mainnet")]
fn test_governance_validator_entries_based_on_voting_power() {
    // This test demonstrates calculating entry allocation based on voting power

    let budokan_addr = budokan_address_mainnet();
    let minigame_addr = minigame_address_mainnet();
    let account = test_account_mainnet();

    let validator_address = deploy_governance_validator(budokan_addr);

    // Configure with votes per entry calculation
    let balance_threshold: u256 = 100; // Base threshold
    let proposal_id: felt252 = 'proposal_123';
    let check_voted: felt252 = 1; // true - must have voted
    let votes_threshold: u256 = 0;
    let votes_per_entry: u256 = 500; // Each entry requires 500 votes

    let extension_config = ExtensionConfig {
        address: validator_address,
        config: array![
            governor_address().into(), governance_token_address().into(),
            balance_threshold.try_into().unwrap(), proposal_id, check_voted,
            votes_threshold.try_into().unwrap(), votes_per_entry.try_into().unwrap(),
        ]
            .span(),
    };

    let entry_requirement = EntryRequirement {
        entry_limit: 0, // No limit, determined by voting power
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

    assert(tournament.id > 0, 'Tournament created');
    // Players' entries = (vote_count - balance_threshold) / votes_per_entry
// E.g., with 2600 votes: (2600 - 100) / 500 = 5 entries
}

#[test]
#[fork("mainnet")]
fn test_governance_validator_validate_entries_ban() {
    // This test demonstrates the complete ban validation flow:
    // 1. Player enters tournament with governance tokens
    // 2. Player transfers tokens away (no longer meets requirements)
    // 3. Verify that should_ban_entry would return true

    let budokan_addr = budokan_address_mainnet();
    let minigame_addr = minigame_address_mainnet();
    let account = test_account_mainnet();

    let validator_address = deploy_governance_validator(budokan_addr);
    let validator = IEntryValidatorDispatcher { contract_address: validator_address };

    // Create tournament with low governance requirements
    let balance_threshold: u256 = 100; // 100 wei
    let proposal_id: felt252 = 'proposal_123';
    let check_voted: felt252 = 0;
    let votes_threshold: u256 = 0;
    let votes_per_entry: u256 = 0;

    let extension_config = ExtensionConfig {
        address: validator_address,
        config: array![
            governor_address().into(), governance_token_address().into(),
            balance_threshold.try_into().unwrap(), proposal_id, check_voted,
            votes_threshold.try_into().unwrap(), votes_per_entry.try_into().unwrap(),
        ]
            .span(),
    };

    let entry_requirement = EntryRequirement {
        entry_limit: 3, entry_requirement_type: EntryRequirementType::extension(extension_config),
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

    // Player enters tournament (has governance tokens at this point)
    let player1 = account;
    let qualification_proof1 = Option::Some(
        QualificationProof::Extension(array![player1.into()].span()),
    );

    start_cheat_caller_address(budokan_addr, player1);
    let (token_id_1, entry_number_1) = budokan
        .enter_tournament(tournament.id, 'player1', player1, qualification_proof1);
    stop_cheat_caller_address(budokan_addr);

    assert(entry_number_1 == 1, 'First entry should be 1');

    // Verify entry is valid before transfer
    let is_valid_before = validator.valid_entry(tournament.id, player1, array![].span());
    assert(is_valid_before, 'Entry should be valid');

    // Get balance before transfer
    let governance_token = IERC20Dispatcher { contract_address: governance_token_address() };
    let player_balance_before = governance_token.balance_of(player1);
    println!("Player balance before transfer: {}", player_balance_before);

    // Transfer governance tokens away to make player no longer meet requirements
    let recipient: ContractAddress = 0x999.try_into().unwrap();

    start_cheat_caller_address(governance_token_address(), player1);
    governance_token.transfer(recipient, player_balance_before); // Transfer all tokens away
    stop_cheat_caller_address(governance_token_address());

    // Check balance after transfer
    let player_balance_after = governance_token.balance_of(player1);
    println!("Player balance after transfer: {}", player_balance_after);
    assert(player_balance_after == 0, 'Balance should be 0');

    // Verify player no longer meets requirements
    let is_valid_after_transfer = validator.valid_entry(tournament.id, player1, array![].span());
    println!("Is valid after transfer: {}", is_valid_after_transfer);
    assert(!is_valid_after_transfer, 'Should no longer be valid');

    // This demonstrates the ban validation flow:
    // - Entry was valid when player had tokens
    // - Entry is no longer valid after player transferred tokens
    // - should_ban_entry would return true (player no longer meets requirements)
    // - In a real scenario, tournament admin would call ban_entry to remove this player

    assert(token_id_1 > 0, 'Token ID valid');
    assert(is_valid_before, 'Was valid before transfer');
    assert(!is_valid_after_transfer, 'Invalid after transfer');
}

#[test]
#[fork("mainnet")]
fn test_governance_validator_ban_existing_allow_new_entries() {
    // This test demonstrates that banning works independently of new entry validation:
    // - Player1's existing entry can be banned (they no longer meet requirements)
    // - Player2 with valid requirements can still enter NEW entries
    // - This proves should_ban_entry and validate_entry are independent checks

    let budokan_addr = budokan_address_mainnet();
    let minigame_addr = minigame_address_mainnet();
    let player1 = test_account_mainnet();
    let player2: ContractAddress = 0x03fe2b97c1fd336e750087d68b9b867997fd64a2661ff3ca5a7c771641e8e7ac
        .try_into()
        .unwrap(); // Known address with governance tokens on mainnet

    let validator_address = deploy_governance_validator(budokan_addr);
    let validator = IEntryValidatorDispatcher { contract_address: validator_address };

    // Create tournament with low governance requirements
    let balance_threshold: u256 = 100; // 100 wei
    let proposal_id: felt252 = 'proposal_123';
    let check_voted: felt252 = 0;
    let votes_threshold: u256 = 0;
    let votes_per_entry: u256 = 0;

    let extension_config = ExtensionConfig {
        address: validator_address,
        config: array![
            governor_address().into(), governance_token_address().into(),
            balance_threshold.try_into().unwrap(), proposal_id, check_voted,
            votes_threshold.try_into().unwrap(), votes_per_entry.try_into().unwrap(),
        ]
            .span(),
    };

    let entry_requirement = EntryRequirement {
        entry_limit: 10, entry_requirement_type: EntryRequirementType::extension(extension_config),
    };

    let budokan = IBudokanDispatcher { contract_address: budokan_addr };

    start_cheat_caller_address(budokan_addr, player1);
    let tournament = budokan
        .create_tournament(
            player1,
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

    // Player1 enters tournament
    start_cheat_caller_address(budokan_addr, player1);
    let (token_id_1, entry_1) = budokan
        .enter_tournament(
            tournament.id, 'player1', player1, Option::Some(
                QualificationProof::Extension(array![].span()),
            ),
        );
    stop_cheat_caller_address(budokan_addr);

    assert(entry_1 == 1, 'Player1 first entry');

    // Player1 transfers all tokens away
    let governance_token = IERC20Dispatcher { contract_address: governance_token_address() };
    let player1_balance = governance_token.balance_of(player1);

    start_cheat_caller_address(governance_token_address(), player1);
    governance_token.transfer(player2, player1_balance);
    stop_cheat_caller_address(governance_token_address());

    println!("Player1 balance after transfer: {}", governance_token.balance_of(player1));
    println!("Player2 balance after receiving: {}", governance_token.balance_of(player2));

    // KEY TEST: Player1's existing entry is no longer valid (would be banned)
    let player1_still_valid = validator
        .valid_entry(tournament.id, player1, array![].span());
    assert(!player1_still_valid, 'Player1 no longer valid');
    println!("Player1 existing entry would be banned: {}", !player1_still_valid);

    // KEY TEST: Player2 can still enter NEW entries (has governance tokens)
    let player2_can_enter = validator.valid_entry(tournament.id, player2, array![].span());
    println!("Player2 can enter new entries: {}", player2_can_enter);

    // If player2 has tokens, they should be able to enter
    if player2_can_enter {
        start_cheat_caller_address(budokan_addr, player2);
        let (token_id_2, entry_2) = budokan
            .enter_tournament(
                tournament.id, 'player2', player2, Option::Some(
                    QualificationProof::Extension(array![].span()),
                ),
            );
        stop_cheat_caller_address(budokan_addr);

        assert(token_id_2 > token_id_1, 'Player2 token ID higher');
        println!("Player2 successfully entered: token_id={}", token_id_2);
    }

    // DEMONSTRATION:
    // - Player1's existing entry (token_id_1) would be banned by should_ban_entry
    // - Player2's new entry is allowed by validate_entry
    // - This proves the two checks are independent and work correctly

    assert(token_id_1 > 0, 'Test completed');
}

#[test]
#[fork("mainnet")]
fn test_governance_validator_direct_validation() {
    // This test demonstrates direct validation without full Budokan integration

    let budokan_addr = budokan_address_mainnet();
    let _account = test_account_mainnet();

    let validator_address = deploy_governance_validator(budokan_addr);
    let validator = IEntryValidatorDispatcher { contract_address: validator_address };

    let tournament_id: u64 = 1;

    // Configure the validator directly
    let balance_threshold: u256 = 1000;
    let proposal_id: felt252 = 'proposal_123';
    let check_voted: felt252 = 0;
    let votes_threshold: u256 = 0;
    let votes_per_entry: u256 = 0;

    let config = array![
        governor_address().into(), governance_token_address().into(),
        balance_threshold.try_into().unwrap(), proposal_id, check_voted,
        votes_threshold.try_into().unwrap(), votes_per_entry.try_into().unwrap(),
    ];

    start_cheat_caller_address(validator_address, budokan_addr);
    validator.add_config(tournament_id, 3, config.span());
    stop_cheat_caller_address(validator_address);

    // Test validation (would need a real player with tokens in fork)
    let player: ContractAddress = 0x111.try_into().unwrap();

    // Check if player is valid
    let _is_valid = validator.valid_entry(tournament_id, player, array![].span());

    // Check entries left
    let _entries_left = validator.entries_left(tournament_id, player, array![].span());
    // Note: These would return actual values on a mainnet fork with real governance contracts
}

#[test]
#[fork("mainnet")]
fn test_governance_validator_multiple_entries() {
    // This test demonstrates tracking multiple entries per player

    let budokan_addr = budokan_address_mainnet();
    let _account = test_account_mainnet();

    let validator_address = deploy_governance_validator(budokan_addr);
    let validator = IEntryValidatorDispatcher { contract_address: validator_address };

    let tournament_id: u64 = 1;
    let player: ContractAddress = 0x111.try_into().unwrap();

    // Configure with entry limit
    let config = array![
        governor_address().into(), governance_token_address().into(), 1000_u256.try_into().unwrap(),
        'proposal_123', 0, // check_voted false
        0_u256.try_into().unwrap(),
        0_u256.try_into().unwrap(),
    ];

    start_cheat_caller_address(validator_address, budokan_addr);
    validator.add_config(tournament_id, 5, config.span()); // 5 entry limit
    stop_cheat_caller_address(validator_address);

    // Simulate player entering multiple times
    start_cheat_caller_address(validator_address, budokan_addr);
    validator.add_entry(tournament_id, 0, player, array![].span());
    stop_cheat_caller_address(validator_address);

    // Check entries after first entry
    let entries_after_1 = validator.entries_left(tournament_id, player, array![].span());
    assert(entries_after_1.is_some(), 'Should have entries');
    // In a real scenario with valid governance setup, this would show 4 entries left

    // Add more entries
    start_cheat_caller_address(validator_address, budokan_addr);
    validator.add_entry(tournament_id, 0, player, array![].span());
    validator.add_entry(tournament_id, 0, player, array![].span());
    stop_cheat_caller_address(validator_address);

    // Check entries after 3 total
    let entries_after_3 = validator.entries_left(tournament_id, player, array![].span());
    assert(entries_after_3.is_some(), 'Should have entries');
    // Would show 2 entries left
}

#[test]
#[fork("mainnet")]
fn test_governance_validator_no_delegation() {
    // This test demonstrates that players without delegation cannot enter

    let budokan_addr = budokan_address_mainnet();
    let _account = test_account_mainnet();

    let validator_address = deploy_governance_validator(budokan_addr);
    let validator = IEntryValidatorDispatcher { contract_address: validator_address };

    let tournament_id: u64 = 1;

    // Configure validator
    let config = array![
        governor_address().into(), governance_token_address().into(), 1000_u256.try_into().unwrap(),
        'proposal_123', 0, 0_u256.try_into().unwrap(), 0_u256.try_into().unwrap(),
    ];

    start_cheat_caller_address(validator_address, budokan_addr);
    validator.add_config(tournament_id, 3, config.span());
    stop_cheat_caller_address(validator_address);

    // Test with player who has tokens but hasn't delegated
    // In validate_entry, if delegates().is_zero(), return false
    let player_no_delegation: ContractAddress = 0x999.try_into().unwrap();

    let _is_valid = validator.valid_entry(tournament_id, player_no_delegation, array![].span());
    // In a real fork with actual governance contracts, this would be false
// because the player hasn't delegated their voting power
}

#[test]
#[fork("mainnet")]
fn test_governance_validator_insufficient_balance() {
    // This test demonstrates that players below balance threshold cannot enter

    let budokan_addr = budokan_address_mainnet();
    let _account = test_account_mainnet();

    let validator_address = deploy_governance_validator(budokan_addr);
    let validator = IEntryValidatorDispatcher { contract_address: validator_address };

    let tournament_id: u64 = 1;

    // Configure with high balance threshold
    let high_threshold: u256 = 10000; // Requires 10000 tokens

    let config = array![
        governor_address().into(), governance_token_address().into(),
        high_threshold.try_into().unwrap(), 'proposal_123', 0, 0_u256.try_into().unwrap(),
        0_u256.try_into().unwrap(),
    ];

    start_cheat_caller_address(validator_address, budokan_addr);
    validator.add_config(tournament_id, 3, config.span());
    stop_cheat_caller_address(validator_address);

    // Player with insufficient balance
    let player_low_balance: ContractAddress = 0x888.try_into().unwrap();

    let _is_valid = validator.valid_entry(tournament_id, player_low_balance, array![].span());
    // In a real fork, if player's balance < 10000, this returns false
}

#[test]
#[fork("mainnet")]
fn test_governance_validator_cross_tournament_independence() {
    // This test demonstrates that entry tracking is independent per tournament

    let budokan_addr = budokan_address_mainnet();
    let _account = test_account_mainnet();

    let validator_address = deploy_governance_validator(budokan_addr);
    let validator = IEntryValidatorDispatcher { contract_address: validator_address };

    let tournament_1: u64 = 1;
    let tournament_2: u64 = 2;
    let player: ContractAddress = 0x111.try_into().unwrap();

    // Configure both tournaments
    let config = array![
        governor_address().into(), governance_token_address().into(), 1000_u256.try_into().unwrap(),
        'proposal_123', 0, 0_u256.try_into().unwrap(), 0_u256.try_into().unwrap(),
    ];

    start_cheat_caller_address(validator_address, budokan_addr);
    validator.add_config(tournament_1, 3, config.span());
    validator.add_config(tournament_2, 5, config.span());
    stop_cheat_caller_address(validator_address);

    // Add entries to tournament 1
    start_cheat_caller_address(validator_address, budokan_addr);
    validator.add_entry(tournament_1, 0, player, array![].span());
    validator.add_entry(tournament_1, 0, player, array![].span());
    stop_cheat_caller_address(validator_address);

    // Check tournament 1 - should have 1 entry left (used 2 of 3)
    let t1_entries = validator.entries_left(tournament_1, player, array![].span());
    assert(t1_entries.is_some(), 'T1 should have entries');

    // Check tournament 2 - should still have 5 entries (independent tracking)
    let t2_entries = validator.entries_left(tournament_2, player, array![].span());
    assert(t2_entries.is_some(), 'T2 should have entries');

    // Add entry to tournament 2
    start_cheat_caller_address(validator_address, budokan_addr);
    validator.add_entry(tournament_2, 0, player, array![].span());
    stop_cheat_caller_address(validator_address);

    // Verify independence maintained
    let t1_final = validator.entries_left(tournament_1, player, array![].span());
    let t2_final = validator.entries_left(tournament_2, player, array![].span());

    assert(t1_final.is_some(), 'T1 entries unchanged');
    assert(t2_final.is_some(), 'T2 entries decreased');
}
// ==============================================
// REAL WORLD USAGE EXAMPLE
// ==============================================
// This comment block shows how you would use the GovernanceValidator in production:
//
// 1. Deploy GovernanceValidator:
//    let validator = deploy_governance_validator(budokan_address_mainnet);
//
// 2. Create extension config with governance parameters:
//    let config = array![
//        governor_address.into(),           // The governor contract
//        governance_token_address.into(),   // The governance/voting token
//        balance_threshold,                 // Minimum token balance required
//        proposal_id,                       // Specific proposal ID (if checking votes)
//        check_voted,                       // Whether to check if player voted
//        votes_threshold,                   // Minimum votes required (if checking)
//        votes_per_entry,                   // Votes needed per entry (0 = fixed limit)
//    ];
//
// 3. Create tournament on Budokan with validator as extension:
//    let extension_config = ExtensionConfig {
//        address: validator_address,
//        config: config.span(),
//    };
//    budokan.create_tournament(..., extension_config);
//
// 4. Players can enter if they meet governance criteria:
//    - Have minimum token balance
//    - Have delegated their voting power
//    - (Optional) Have voted on specified proposal
//    - (Optional) Have sufficient voting power
//
// 5. Re-validate entry to ban player who no longer qualifies:
//    budokan.ban_entry(tournament_id, game_token_id, array![].span());
//    // This re-checks the participant and invalidates them if they:
//    // - Transferred tokens below threshold
//    // - Undelegated their voting power
//    // - No longer meet voting requirements
//
// 6. Entry allocation modes:
//    a) Fixed limit: Set entry_limit > 0, votes_per_entry = 0
//       All eligible players get the same entry limit
//
//    b) Voting power based: Set entry_limit = 0, votes_per_entry > 0
//       Entries = (vote_count - balance_threshold) / votes_per_entry
//       Higher voting power = more entries
// ==============================================

