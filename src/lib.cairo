pub mod entry_validator;

pub mod examples {
    pub mod governance_validator;
    pub mod snapshot_validator;
}

pub mod tests {
    pub mod mocks {
        pub mod entry_validator_mock;
        pub mod erc721_mock;
        pub mod governance_validator_mock;
        pub mod open_entry_validator_mock;
        pub mod opus_troves_mock;
    }
    #[cfg(test)]
    pub mod test_entry_validator;
    #[cfg(test)]
    pub mod test_governance_validator;
    // #[cfg(test)]
    // pub mod test_snapshot_validator_fork;
    #[cfg(test)]
    pub mod test_snapshot_validator_budokan_fork;
}
