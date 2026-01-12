#!/bin/bash

# Opus Troves Validator Deployment Script (Debt-Based)
# Deploys the OpusTrovesValidator contract to Starknet

set -euo pipefail

# Find .env relative to script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/../.env" ]; then
    set -a
    source "$SCRIPT_DIR/../.env"
    set +a
    echo "Loaded environment variables from $SCRIPT_DIR/../.env"
fi

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check deployment environment
STARKNET_NETWORK="${STARKNET_NETWORK:-default}"

# Map network to sncast profile
case "$STARKNET_NETWORK" in
    "mainnet")
        SNCAST_PROFILE="mainnet"
        ;;
    "sepolia")
        SNCAST_PROFILE="sepolia"
        ;;
    *)
        SNCAST_PROFILE="default"
        ;;
esac

# Check if required environment variables are set
print_info "Checking environment variables..."

required_vars=("BUDOKAN_ADDRESS")

missing_vars=()

# Debug output for environment variables
print_info "Environment variables loaded:"
echo "  STARKNET_NETWORK: $STARKNET_NETWORK"
echo "  SNCAST_PROFILE: $SNCAST_PROFILE"
echo "  STARKNET_RPC: ${STARKNET_RPC:-<from profile>}"
echo "  BUDOKAN_ADDRESS: ${BUDOKAN_ADDRESS:-<not set>}"

# Build URL flag if STARKNET_RPC is provided
URL_FLAG=""
if [ -n "${STARKNET_RPC:-}" ]; then
    URL_FLAG="--url $STARKNET_RPC"
fi

for var in "${required_vars[@]}"; do
    if [ -z "${!var:-}" ]; then
        missing_vars+=("$var")
    fi
done

if [ ${#missing_vars[@]} -ne 0 ]; then
    print_error "The following required environment variables are not set:"
    for var in "${missing_vars[@]}"; do
        echo "  - $var"
    done
    echo "Please set these variables before running the script."
    exit 1
fi

# ============================
# DISPLAY CONFIGURATION
# ============================

print_info "Deployment Configuration:"
echo "  Network: $STARKNET_NETWORK"
echo "  Profile: $SNCAST_PROFILE"
echo "  RPC: ${STARKNET_RPC:-<from profile>}"
echo ""

# Confirm deployment
if [ "${SKIP_CONFIRMATION:-false}" != "true" ]; then
    read -p "Continue with deployment? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Deployment cancelled"
        exit 0
    fi
fi

# ============================
# BUILD CONTRACTS
# ============================

print_info "Building contracts..."
cd "$SCRIPT_DIR/.."
scarb build

if [ ! -f "target/dev/budokan_extensions_OpusTrovesValidator.contract_class.json" ]; then
    print_error "OpusTrovesValidator contract build failed or contract file not found"
    print_error "Expected: target/dev/budokan_extensions_OpusTrovesValidator.contract_class.json"
    echo "Available contract files:"
    ls -la target/dev/*.contract_class.json 2>/dev/null || echo "No contract files found"
    exit 1
fi

# ============================
# CALCULATE CLASS HASH FIRST
# ============================

print_info "Calculating class hash from artifact..."
CLASS_HASH_OUTPUT=$(sncast --profile $SNCAST_PROFILE utils class-hash \
    --contract-name OpusTrovesValidator \
    --package budokan_extensions 2>&1)
CLASS_HASH=$(echo "$CLASS_HASH_OUTPUT" | grep -oE '0x[0-9a-fA-F]+' | head -1)

if [ -z "$CLASS_HASH" ]; then
    print_error "Could not calculate class hash from artifact"
    echo "Class hash output: $CLASS_HASH_OUTPUT"
    exit 1
fi
print_info "Class hash: $CLASS_HASH"

# ============================
# DECLARE OPUS TROVES VALIDATOR V2
# ============================

print_info "Declaring OpusTrovesValidator contract..."

DECLARE_OUTPUT=$(sncast --profile $SNCAST_PROFILE declare \
    $URL_FLAG \
    --contract-name OpusTrovesValidator \
    --package budokan_extensions \
    2>&1) || true

# Check declaration result
if echo "$DECLARE_OUTPUT" | grep -qi "class hash:"; then
    print_info "Contract declared successfully"
    print_info "Waiting for declaration to be confirmed..."
    sleep 5
elif echo "$DECLARE_OUTPUT" | grep -qi "already declared"; then
    print_warning "Contract already declared, proceeding with deployment..."
else
    if echo "$DECLARE_OUTPUT" | grep -qi "error"; then
        print_error "Declaration failed"
        echo "Declaration output: $DECLARE_OUTPUT"
        exit 1
    fi
    print_info "Declaration submitted, waiting for confirmation..."
    sleep 5
fi

# ============================
# DEPLOY OPUS TROVES VALIDATOR V2
# ============================

print_info "Deploying OpusTrovesValidator contract..."

# Constructor parameters: budokan_address
print_info "Using BUDOKAN_ADDRESS: $BUDOKAN_ADDRESS"
print_info "Note: OpusTrovesValidator uses registration_only=false (allows banning)"

# Retry deployment up to 3 times
MAX_RETRIES=3
RETRY_COUNT=0
CONTRACT_ADDRESS=""

while [ $RETRY_COUNT -lt $MAX_RETRIES ] && [ -z "$CONTRACT_ADDRESS" ]; do
    RETRY_COUNT=$((RETRY_COUNT + 1))

    if [ $RETRY_COUNT -gt 1 ]; then
        print_warning "Retry attempt $RETRY_COUNT of $MAX_RETRIES..."
        sleep 3
    fi

    DEPLOY_OUTPUT=$(sncast --profile $SNCAST_PROFILE deploy \
        $URL_FLAG \
        --class-hash "$CLASS_HASH" \
        --constructor-calldata "$BUDOKAN_ADDRESS" \
        2>&1) || true

    # Extract contract address from output
    if echo "$DEPLOY_OUTPUT" | grep -qi "contract address:"; then
        CONTRACT_ADDRESS=$(echo "$DEPLOY_OUTPUT" | grep -i "contract address:" | awk '{print $3}')
    elif echo "$DEPLOY_OUTPUT" | grep -q "contract_address:"; then
        CONTRACT_ADDRESS=$(echo "$DEPLOY_OUTPUT" | grep "contract_address:" | awk '{print $2}')
    elif echo "$DEPLOY_OUTPUT" | grep -qiE "error|failed"; then
        print_warning "Deployment attempt failed: $(echo "$DEPLOY_OUTPUT" | head -1)"
    fi
done

if [ -z "$CONTRACT_ADDRESS" ]; then
    print_error "Failed to deploy contract after $MAX_RETRIES attempts"
    echo "Last deploy output: $DEPLOY_OUTPUT"
    exit 1
fi

print_info "OpusTrovesValidator contract deployed at address: $CONTRACT_ADDRESS"

# ============================
# SAVE DEPLOYMENT INFO
# ============================

DEPLOYMENT_FILE="deployments/opus_troves_validator_$(date +%Y%m%d_%H%M%S).json"
mkdir -p deployments

cat > "$DEPLOYMENT_FILE" << EOF
{
  "network": "$STARKNET_NETWORK",
  "profile": "$SNCAST_PROFILE",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "opus_troves_validator": {
    "address": "$CONTRACT_ADDRESS",
    "class_hash": "$CLASS_HASH",
    "description": "Opus Troves Validator - debt-based tournament entries with optional asset filtering",
    "registration_only": false,
    "features": [
      "Debt-based entries using borrowed yin from Opus Protocol",
      "Asset filtering: wildcard (all troves) or filtered by specific collateral types",
      "Sums debt only from troves matching asset requirements",
      "Dynamic entry calculation: (total_debt - threshold) / value_per_entry",
      "Automatic banning when debt falls below threshold or exceeds quota"
    ]
  }
}
EOF

print_info "Deployment info saved to: $DEPLOYMENT_FILE"

# ============================
# DEPLOYMENT SUMMARY
# ============================

echo
print_info "=== DEPLOYMENT SUCCESSFUL ==="
echo
echo "Opus Troves Validator Contract (Debt-Based):"
echo "  Address: $CONTRACT_ADDRESS"
echo "  Class Hash: $CLASS_HASH"
echo "  Registration Only: false (allows banning)"
echo ""

echo "Features:"
echo "  - Debt-based entries using borrowed yin from Opus Protocol"
echo "  - Optional asset filtering: target specific borrower communities"
echo "  - Wildcard mode: sums debt across ALL troves (any collateral)"
echo "  - Filtered mode: sums debt only from troves backed by specified assets"
echo "  - Dynamic entry calculation: (total_debt - threshold) / value_per_entry"
echo "  - Automatic banning when debt falls below threshold or quota exceeded"
echo ""

echo "Configuration:"
echo "  config[0]: asset_count (u8) - 0 = wildcard (all troves), N = filter by N assets"
echo "  config[1..N]: asset addresses (if asset_count > 0)"
echo "  config[N+1]: threshold (u128) - minimum yin debt (WAD UNITS: 1e18 = 1 yin)"
echo "  config[N+2]: value_per_entry (u128) - yin per entry (WAD UNITS: 1e18 = 1 yin)"
echo "  config[N+3]: max_entries (u8) - maximum entries cap (0 = no cap)"
echo ""
echo "IMPORTANT: Use WAD units (18 decimals) for maximum precision!"
echo "  1 yin = 1000000000000000000 (1e18)"
echo "  0.5 yin = 500000000000000000 (0.5e18)"
echo ""

echo "Next steps:"
echo "1. Verify the contract on Starkscan/Voyager"
echo "2. Configure tournament entry rules using add_config():"
echo "   - Set asset_count (0 for wildcard, N for asset filtering)"
echo "   - Set asset addresses (if filtering)"
echo "   - Set threshold (minimum yin debt required)"
echo "   - Set value_per_entry (yin required per entry)"
echo "   - Set max_entries (cap on entries, 0 for unlimited)"
echo "3. Integrate with your tournament creation flow"
echo ""

echo "To interact with the contract:"
echo "  export OPUS_TROVES_VALIDATOR=$CONTRACT_ADDRESS"
echo "  export STRK_ADDRESS=0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d"
echo "  export WSTETH_ADDRESS=0x042b8f0484674ca266ac5d08e4ac6a3fe65bd3129795def2dca5c34ecc5f96d2"
echo ""

echo "Example configurations:"
echo ""
echo "  # Wildcard - All borrowers, 1 yin per entry"
echo "  sncast --profile $SNCAST_PROFILE --url \$STARKNET_RPC invoke \\"
echo "    --contract-address \$OPUS_TROVES_VALIDATOR \\"
echo "    --function add_config \\"
echo "    --calldata <tournament_id> <entry_limit> 0 1000000000000000000 1000000000000000000 50"
echo "  # Config: asset_count=0 (wildcard), threshold=1 yin, value_per_entry=1 yin, max=50"
echo ""
echo "  # STRK borrowers only, 0.5 yin per entry"
echo "  sncast --profile $SNCAST_PROFILE --url \$STARKNET_RPC invoke \\"
echo "    --contract-address \$OPUS_TROVES_VALIDATOR \\"
echo "    --function add_config \\"
echo "    --calldata <tournament_id> <entry_limit> 1 \$STRK_ADDRESS 10000000000000000000 500000000000000000 20"
echo "  # Config: asset_count=1, asset=STRK, threshold=10 yin, value_per_entry=0.5 yin, max=20"
echo ""
echo "  # Blue chip borrowers (STRK or wstETH), 2 yin per entry"
echo "  sncast --profile $SNCAST_PROFILE --url \$STARKNET_RPC invoke \\"
echo "    --contract-address \$OPUS_TROVES_VALIDATOR \\"
echo "    --function add_config \\"
echo "    --calldata <tournament_id> <entry_limit> 2 \$STRK_ADDRESS \$WSTETH_ADDRESS 5000000000000000000 2000000000000000000 0"
echo "  # Config: asset_count=2, assets=STRK+wstETH, threshold=5 yin, value_per_entry=2 yin, max=0 (unlimited)"
echo ""
