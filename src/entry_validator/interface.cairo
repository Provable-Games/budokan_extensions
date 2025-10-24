use starknet::ContractAddress;

pub const IENTRY_VALIDATOR_ID: felt252 =
    0x01158754d5cc62137c4de2cbd0e65cbd163990af29f0182006f26fe0cac00bb6;

// Simple qualification proof for testing
#[derive(Drop, Serde)]
pub struct QualificationProof {
    pub token_id: u256,
}

#[starknet::interface]
pub trait IEntryValidator<TState> {
    fn valid_entry(self: @TState, player_address: ContractAddress, qualification_proof: Option<QualificationProof>) -> bool;
}
