use starknet::ContractAddress;

pub const IENTRY_VALIDATOR_ID: felt252 =
    0x01158754d5cc62137c4de2cbd0e65cbd163990af29f0182006f26fe0cac00bb6;

#[starknet::interface]
pub trait IEntryValidator<TState> {
    fn valid_entry(
        self: @TState,
        tournament_id: u64,
        player_address: ContractAddress,
        qualification: Span<felt252>,
    ) -> bool;
    fn entries_left(
        self: @TState,
        tournament_id: u64,
        player_address: ContractAddress,
        qualification: Span<felt252>,
    ) -> Option<u8>;
    fn add_config(ref self: TState, tournament_id: u64, config: Span<felt252>);
    fn add_entry(ref self: TState, tournament_id: u64, player_address: ContractAddress, qualification: Span<felt252>);
}
