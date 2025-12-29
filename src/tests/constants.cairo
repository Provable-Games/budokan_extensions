use starknet::ContractAddress;

// ==============================================
// MAINNET CONTRACT ADDRESSES
// ==============================================

// Budokan contract address on mainnet
pub fn budokan_address_mainnet() -> ContractAddress {
    0x079b2d43a88db9d5111797edf45dda7d2a51e3aa5b6ed3e5c6a5410e88f50433.try_into().unwrap()
}

// Minigame contract address on mainnet
pub fn minigame_address_mainnet() -> ContractAddress {
    0x5e2dfbdc3c193de629e5beb116083b06bd944c1608c9c793351d5792ba29863.try_into().unwrap()
}

// Test account address on mainnet
pub fn test_account_mainnet() -> ContractAddress {
    0x077b8Ed8356a7C1F0903Fc4bA6E15F9b09CF437ce04f21B2cBf32dC2790183d0.try_into().unwrap()
}

// ==============================================
// SEPOLIA CONTRACT ADDRESSES
// ==============================================

// Budokan contract address on sepolia
pub fn budokan_address_sepolia() -> ContractAddress {
    0x027649a648ce25712cf90a3b32b9f15f86edb21293227d0b3cc689987c77a02b.try_into().unwrap()
}

// Minigame contract address on sepolia
pub fn minigame_address_sepolia() -> ContractAddress {
    0x07ba8a9d724cc37b79663030693cfb876faced7d8abce2c6cf34c0b887a2614d.try_into().unwrap()
}

// Test account address on sepolia
pub fn test_account_sepolia() -> ContractAddress {
    0x077b8Ed8356a7C1F0903Fc4bA6E15F9b09CF437ce04f21B2cBf32dC2790183d0.try_into().unwrap()
}

// ==============================================
// GOVERNANCE CONTRACT ADDRESSES
// ==============================================

// Governance token contract address on mainnet
pub fn governance_token_address() -> ContractAddress {
    0x042dd777885ad2c116be96d4d634abc90a26a790ffb5871e037dd5ae7d2ec86b.try_into().unwrap()
}

// Governor contract address on mainnet
pub fn governor_address() -> ContractAddress {
    0x050897ea9df71b661b8eac53162be37552e729ee9d33a6f9ae0b61c95a11209e.try_into().unwrap()
}

// ==============================================
// ERC20 TOKEN ADDRESSES
// ==============================================

// ETH token contract address on mainnet (Starknet ETH)
pub fn eth_token_address() -> ContractAddress {
    0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7.try_into().unwrap()
}

// STRK token contract address on mainnet
pub fn strk_token_address() -> ContractAddress {
    0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d.try_into().unwrap()
}

// LORDS token contract address on mainnet
pub fn lords_token_address() -> ContractAddress {
    0x0124aeb495b947201f5fac96fd1138e326ad86195b98df6dec9009158a533b49.try_into().unwrap()
}
