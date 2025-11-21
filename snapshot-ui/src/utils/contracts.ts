// Snapshot Validator Contract ABI and Address
export const SNAPSHOT_VALIDATOR_ADDRESS = "0x079e3a4b02a079672aae7f128347b11bd1a50cf9f94e795064d9e601326483d3";

export const SNAPSHOT_VALIDATOR_ABI = [
  {
    type: "struct",
    name: "budokan_extensions::examples::snapshot_validator::Entry",
    members: [
      { name: "address", type: "core::starknet::contract_address::ContractAddress" },
      { name: "count", type: "core::integer::u8" },
    ],
  },
  {
    name: "create_snapshot",
    type: "function",
    inputs: [],
    outputs: [{ name: "snapshot_id", type: "core::integer::u64" }],
    state_mutability: "external",
  },
  {
    name: "upload_snapshot_data",
    type: "function",
    inputs: [
      { name: "snapshot_id", type: "core::integer::u64" },
      {
        name: "snapshot_values",
        type: "core::array::Span::<budokan_extensions::examples::snapshot_validator::Entry>",
      },
    ],
    outputs: [],
    state_mutability: "external",
  },
  {
    name: "lock_snapshot",
    type: "function",
    inputs: [{ name: "snapshot_id", type: "core::integer::u64" }],
    outputs: [],
    state_mutability: "external",
  },
  {
    type: "enum",
    name: "budokan_extensions::examples::snapshot_validator::SnapshotStatus",
    variants: [
      { name: "Created", type: "()" },
      { name: "InProgress", type: "()" },
      { name: "Locked", type: "()" },
    ],
  },
  {
    type: "struct",
    name: "budokan_extensions::examples::snapshot_validator::SnapshotMetadata",
    members: [
      { name: "owner", type: "core::starknet::contract_address::ContractAddress" },
      { name: "status", type: "budokan_extensions::examples::snapshot_validator::SnapshotStatus" },
    ],
  },
  {
    type: "enum",
    name: "core::option::Option::<budokan_extensions::examples::snapshot_validator::SnapshotMetadata>",
    variants: [
      { name: "Some", type: "budokan_extensions::examples::snapshot_validator::SnapshotMetadata" },
      { name: "None", type: "()" },
    ],
  },
  {
    name: "get_snapshot_metadata",
    type: "function",
    inputs: [{ name: "snapshot_id", type: "core::integer::u64" }],
    outputs: [
      {
        name: "metadata",
        type: "core::option::Option::<budokan_extensions::examples::snapshot_validator::SnapshotMetadata>",
      },
    ],
    state_mutability: "view",
  },
  {
    name: "get_snapshot_entry",
    type: "function",
    inputs: [
      { name: "snapshot_id", type: "core::integer::u64" },
      { name: "player_address", type: "core::starknet::contract_address::ContractAddress" },
    ],
    outputs: [{ name: "count", type: "core::integer::u8" }],
    state_mutability: "view",
  },
  {
    name: "is_snapshot_locked",
    type: "function",
    inputs: [{ name: "snapshot_id", type: "core::integer::u64" }],
    outputs: [{ name: "locked", type: "core::bool" }],
    state_mutability: "view",
  },
] as const;

// Type definitions
export interface Entry {
  address: string;
  count: number;
}

export interface SnapshotMetadata {
  owner: string;
  status: "Created" | "InProgress" | "Locked";
}