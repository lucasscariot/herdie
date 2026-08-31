use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Enum)]
pub enum HostTrustDecision {
    Trusted,
    Unknown { presented: String },
    Mismatch { expected: String, presented: String },
}

pub struct HostTrust;

impl HostTrust {
    pub fn verify(stored: Option<&str>, presented: &str) -> HostTrustDecision {
        match stored {
            None => HostTrustDecision::Unknown {
                presented: presented.into(),
            },
            Some(expected) if expected == presented => HostTrustDecision::Trusted,
            Some(expected) => HostTrustDecision::Mismatch {
                expected: expected.into(),
                presented: presented.into(),
            },
        }
    }
}
