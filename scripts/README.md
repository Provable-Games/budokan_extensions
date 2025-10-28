# Deployment Scripts

This directory contains deployment scripts for the Budokan Extensions contracts.

## Available Scripts

### `deploy_open_entry_validator.sh`

Deploys the Open Entry Validator contract, which allows all players to enter without any token requirements.

**Usage:**

```bash
# 1. Copy the example environment file and configure it
cp .env.example .env

# 2. Edit .env with your configuration
# Set STARKNET_NETWORK, STARKNET_ACCOUNT, STARKNET_RPC, and STARKNET_PK

# 3. Run the deployment script
./scripts/deploy_open_entry_validator.sh
```

**Requirements:**
- `starkli` installed and available in PATH
- `scarb` installed for building contracts
- Configured `.env` file with Starknet credentials

**What it does:**
1. Checks environment variables
2. Builds the contract using `scarb build`
3. Declares the contract on Starknet
4. Deploys the contract (no constructor parameters)
5. Saves deployment information to `deployments/open_entry_validator_*.json`

**Output:**
- Contract address
- Class hash
- Deployment timestamp
- Network information

---

### `deploy_governance.sh`

Deploys the complete governance system including SurvivorToken, SurvivorGovernorController, and SurvivorGovernor contracts.

**Usage:**

```bash
./scripts/deploy_governance.sh
```

See the script comments for detailed configuration options.

---

## Environment Variables

Create a `.env` file in the project root with the following variables:

```bash
# Required for standard deployment
STARKNET_NETWORK=sepolia
STARKNET_ACCOUNT=/path/to/account.json
STARKNET_RPC=https://starknet-sepolia.infura.io/v3/YOUR_API_KEY
STARKNET_PK=0x...

# Optional
DEPLOY_TO_SLOT=false  # Set to true for Slot deployment
SKIP_CONFIRMATION=false  # Set to true to skip confirmation prompt
```

### Getting RPC Endpoints

**Free Options (Rate Limited):**
- Nethermind: `https://free-rpc.nethermind.io/sepolia-juno`
- Blast API: `https://starknet-sepolia.blastapi.io/YOUR_API_KEY`

**Recommended (Better Performance):**
- Infura: `https://starknet-sepolia.infura.io/v3/YOUR_API_KEY`
- Alchemy: `https://starknet-sepolia.g.alchemy.com/v2/YOUR_API_KEY`

### Security Best Practices

⚠️ **NEVER commit your `.env` file or private keys to version control!**

- Keep your private key secure
- Use environment variables or secure key management in production
- Consider using Starknet account abstraction for better security
- For production deployments, use hardware wallets or secure key management systems

---

## Deployment Information

Deployment information is automatically saved to the `deployments/` directory with timestamps.

Example deployment file structure:

```json
{
  "network": "sepolia",
  "timestamp": "2025-01-15T10:30:00Z",
  "open_entry_validator": {
    "address": "0x...",
    "class_hash": "0x...",
    "description": "Open entry validator that allows all players to enter"
  }
}
```

---

## Verifying Deployments

After deployment, verify your contracts on:

- **Sepolia Testnet:**
  - [Starkscan Sepolia](https://sepolia.starkscan.co/)
  - [Voyager Sepolia](https://sepolia.voyager.online/)

- **Mainnet:**
  - [Starkscan](https://starkscan.co/)
  - [Voyager](https://voyager.online/)

---

## Troubleshooting

### "Contract already declared" Error

This is not an error - the script will automatically use the existing class hash and continue with deployment.

### "Failed to extract address from account file"

Make sure your `STARKNET_ACCOUNT` points to a valid account JSON file with an `address` field.

### "Build failed"

Ensure you're running the script from the project root or that paths are correctly configured. The script automatically navigates to the correct directory.

### RPC Connection Issues

- Check your RPC endpoint is correct and accessible
- Verify your API key is valid (if using Infura/Alchemy)
- Try a different RPC provider
- Check network connectivity

---

## Testing Deployed Contracts

After deployment, you can test the contract:

```bash
# Set the contract address from deployment output
export ENTRY_VALIDATOR=0x...

# Test that anyone can enter (should return true)
starkli call $ENTRY_VALIDATOR valid_entry \
  0x123... 0

# Where:
# - 0x123... is any player address
# - 0 is the empty qualification proof (Span length)
```

Expected result: The contract should return `true` for any player address, confirming that the open entry validator allows unrestricted access.
