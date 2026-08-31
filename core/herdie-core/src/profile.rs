use serde::{Deserialize, Serialize};
use thiserror::Error;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Record)]
pub struct ConnectionProfile {
    pub id: String,
    pub name: String,
    pub host: String,
    pub port: u16,
    pub username: String,
}

impl ConnectionProfile {
    pub fn new(
        id: String,
        name: String,
        host: String,
        port: u16,
        username: String,
    ) -> Result<Self, CoreError> {
        let id = required("id", id)?;
        let name = required("name", name)?;
        let host = required("host", host)?;
        let username = required("username", username)?;
        if port == 0 {
            return Err(CoreError::InvalidProfile {
                field: "port".into(),
            });
        }

        Ok(Self {
            id,
            name,
            host,
            port,
            username,
        })
    }

    pub(crate) fn validated(self) -> Result<Self, CoreError> {
        Self::new(self.id, self.name, self.host, self.port, self.username)
    }
}

fn required(field: &str, value: String) -> Result<String, CoreError> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        Err(CoreError::InvalidProfile {
            field: field.into(),
        })
    } else {
        Ok(trimmed.into())
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Error, uniffi::Error)]
pub enum CoreError {
    #[error("connection profile field '{field}' is invalid")]
    InvalidProfile { field: String },
    #[error("terminal dimensions must be greater than zero")]
    InvalidTerminalSize,
    #[error("failed to encode terminal snapshot: {message}")]
    SnapshotEncoding { message: String },
    #[error("transport failed: {message}")]
    Transport { message: String },
}
