# Fork Testing with Starknet Foundry

This document explains how to use Starknet Foundry's fork testing feature to test the SnapshotValidator extension against deployed contracts on mainnet or testnet.

## Overview

Fork testing allows you to:
- Test against real deployed contracts (Budokan, minigames, etc.)
- Deploy and test new extensions on a forked network
- Verify integration without deploying to live networks
- Debug issues with actual on-chain state

## Configuration

The fork configuration is defined in `Scarb.toml`:

```toml
[[tool.snforge.fork]]
name = "sepolia"
url = "https://api.cartridge.gg/x/starknet/sepolia"
block_id.tag = "latest"

[[tool.snforge.fork]]
name = "mainnet"
url = "https://api.cartridge.gg/x/starknet/mainnet"
block_id.tag = "latest"
```

### Using a Specific Block

For reproducible tests, specify a block number instead of "latest":

```toml
[[tool.snforge.fork]]
name = "sepolia"
url = "https://api.cartridge.gg/x/starknet/sepolia"
block_id.number = 123456
```

## Test Files

### 1. `test_snapshot_validator_fork.cairo`

Basic fork tests that verify SnapshotValidator functionality without Budokan integration.

**Tests included:**
- Deploy SnapshotValidator on forked network
- Insert snapshot data
- Validate entry logic
- Track entries left
- Add entries and track usage
- Multiple tournament scenarios
- Large batch snapshot insertion
- Snapshot data updates

**Run these tests:**

```bash
# Run all basic fork tests on mainnet (default network)
snforge test test_snapshot_validator_fork --fork-name mainnet

# Run a specific test
snforge test test_snapshot_validator_fork_deploy --fork-name mainnet

# Run on sepolia (change #[fork("mainnet")] to #[fork("sepolia")] in test file first)
snforge test test_snapshot_validator_fork --fork-name sepolia
```

### 2. `test_snapshot_validator_budokan_fork.cairo`

Integration tests with Budokan contract showing real-world usage patterns.

**Tests included:**
- Create tournament on Budokan with SnapshotValidator
- Enter tournaments using snapshot validation
- Multiple entries per player
- Unauthorized entry attempts
- Update snapshots mid-lifecycle
- Cross-tournament entry tracking

**Setup required:**

The tests are pre-configured with mainnet contract addresses:
- **Budokan (Mainnet)**: `0x58f888ba5897efa811eca5e5818540d35b664f4281660cd839cd5a4b0bf4582`
- **Minigame (Mainnet)**: `0x5e2dfbdc3c193de629e5beb116083b06bd944c1608c9c793351d5792ba29863`
- **Test Account (Mainnet)**: `0x077b8Ed8356a7C1F0903Fc4bA6E15F9b09CF437ce04f21B2cBf32dC2790183d0`

To use these tests:

1. Remove the `#[ignore]` attribute from tests you want to run

2. Run the tests:

```bash
snforge test test_snapshot_validator_budokan --fork-name mainnet
```

## Common Usage Patterns

### Pattern 1: Testing Against Deployed Budokan

```cairo
#[test]
#[fork("sepolia")]
fn test_my_extension() {
    // 1. Deploy your extension
    let validator = deploy_snapshot_validator(budokan_address);

    // 2. Set up test data
    let snapshots = array![
        Snapshot { address: player1, entries: 3 },
        Snapshot { address: player2, entries: 5 },
    ];
    validator.insert_snapshots(snapshots.span());

    // 3. Create tournament on Budokan
    let extension_config = ExtensionConfig {
        address: validator_address,
        config: array![].span(),
    };
    // ... create tournament with extension

    // 4. Test entry logic
    // ... enter tournament and verify
}
```

### Pattern 2: Testing With Specific Block State

```cairo
#[test]
#[fork("sepolia")]
fn test_historical_state() {
    // Fork at specific block to ensure consistent state
    // Configure in Scarb.toml with block_id.number

    let validator = deploy_snapshot_validator(budokan_address);
    // ... test with known historical state
}
```

### Pattern 3: Testing Multiple Scenarios

```cairo
#[test]
#[fork("sepolia")]
fn test_entry_scenarios() {
    let validator_address = deploy_snapshot_validator(budokan_address);
    let validator = ISnapshotValidatorDispatcher { contract_address: validator_address };

    // Scenario 1: Player with entries can enter
    let player1: ContractAddress = 0x111.try_into().unwrap();
    validator.insert_snapshots(array![
        Snapshot { address: player1, entries: 3 }
    ].span());

    let entry_validator = IEntryValidatorDispatcher {
        contract_address: validator_address
    };
    assert(entry_validator.valid_entry(1, player1, array![].span()), 'Valid');

    // Scenario 2: Player without entries cannot enter
    let player2: ContractAddress = 0x222.try_into().unwrap();
    assert(!entry_validator.valid_entry(1, player2, array![].span()), 'Invalid');
}
```

## Real-World Deployment Flow

### Step 1: Deploy SnapshotValidator

```bash
# Using the deployment script
BUDOKAN_ADDRESS=0x... ./scripts/deploy_snapshot_validator.sh
```

### Step 2: Prepare Snapshot Data

Off-chain, collect eligible players and their entry counts:

```python
snapshot_data = [
    {"address": "0x111...", "entries": 3},
    {"address": "0x222...", "entries": 5},
    {"address": "0x333...", "entries": 2},
]
```

### Step 3: Insert Snapshots

Call `insert_snapshots` on the deployed validator:

```bash
# Using starkli or similar
starkli invoke $VALIDATOR_ADDRESS insert_snapshots \
    <serialized_snapshot_array>
```

### Step 4: Create Tournament

Create a tournament on Budokan with the validator as an extension:

```cairo
let extension_config = ExtensionConfig {
    address: validator_address,
    config: array![].span(),
};

let entry_requirement = EntryRequirement {
    entry_limit: 0, // Controlled by snapshot
    entry_requirement_type: EntryRequirementType::extension(extension_config),
};

budokan.create_tournament(
    creator,
    metadata,
    schedule,
    game_config,
    Option::None,
    Option::Some(entry_requirement),
);
```

### Step 5: Players Enter

Players can now enter if they're in the snapshot:

```cairo
let qualification_proof = Option::Some(
    QualificationProof::Extension(array![player_address.into()].span())
);

budokan.enter_tournament(
    tournament_id,
    player_name,
    player_address,
    qualification_proof,
);
```

## Troubleshooting

### RPC Errors

If you encounter RPC errors like "data did not match any variant":
- Try a different RPC endpoint
- Use a specific block number instead of "latest"
- Check RPC endpoint is accessible and supports the version

### Test Failures

If tests fail:
1. Verify contract addresses are correct for the network
2. Check that the forked network state is as expected
3. Ensure you have the right block number
4. Verify RPC endpoint is working: `curl $RPC_URL`

### Permission Errors

Some operations require specific permissions:
- Use `start_cheat_caller_address` to impersonate authorized accounts
- Ensure the test account has necessary permissions on deployed contracts

## Advanced Usage

### Using Custom RPC

Override the RPC URL at runtime:

```bash
snforge test --fork-url $STARKNET_RPC_URL --fork-block-number 123456
```

### Running Subset of Fork Tests

```bash
# Run only fork tests
snforge test --fork-name sepolia

# Run specific test pattern
snforge test snapshot_validator_fork --fork-name sepolia

# Run with detailed output
snforge test test_snapshot_validator_fork_deploy --fork-name sepolia --detailed-resources
```

### Environment Variables

Set up environment variables for convenience:

```bash
export STARKNET_RPC_SEPOLIA="https://api.cartridge.gg/x/starknet/sepolia"
export STARKNET_RPC_MAINNET="https://api.cartridge.gg/x/starknet/mainnet"
export BUDOKAN_ADDRESS="0x..."
export MINIGAME_ADDRESS="0x..."
```

## Best Practices

1. **Use specific block numbers** for CI/CD to ensure reproducibility
2. **Test against testnet first** before mainnet validation
3. **Keep fork tests separate** from regular unit tests
4. **Document required addresses** at the top of test files
5. **Use #[ignore] for integration tests** that require specific setup
6. **Clean up test state** if modifying on-chain state
7. **Verify gas usage** on forked networks matches expectations

## Resources

- [Starknet Foundry Documentation](https://foundry-rs.github.io/starknet-foundry/)
- [Starknet Foundry Fork Testing](https://foundry-rs.github.io/starknet-foundry/testing/fork-testing.html)
- [Budokan Documentation](https://docs.budokan.gg/)

## Examples

See the test files for complete examples:
- `src/tests/test_snapshot_validator_fork.cairo` - Basic validator tests
- `src/tests/test_snapshot_validator_budokan_fork.cairo` - Budokan integration tests
