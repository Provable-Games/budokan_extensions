pub mod examples {
    pub mod erc20_balance_validator;
    pub mod governance_validator;
    pub mod opus_troves_validator;
    pub mod snapshot_validator;
    pub mod tournament_validator;
}

pub mod tests {
    pub mod constants;
    pub mod mocks {
        pub mod entry_validator_mock;
        pub mod erc721_mock;
        pub mod open_entry_validator_mock;
    }
    #[cfg(test)]
    pub mod test_entry_validator;
    #[cfg(test)]
    pub mod test_erc20_balance_validator_budokan_fork;
    #[cfg(test)]
    pub mod test_governance_validator;
    #[cfg(test)]
    pub mod test_governance_validator_budokan_fork;
    #[cfg(test)]
    pub mod test_opus_troves_validator_budokan_fork;
    // #[cfg(test)]
    // pub mod test_snapshot_validator_fork;
    #[cfg(test)]
    pub mod test_snapshot_validator_budokan_fork;
    #[cfg(test)]
    pub mod test_tournament_validator_budokan_fork;
    #[cfg(test)]
    pub mod test_tournament_validator_integration;
}
