use std::sync::{Arc, Mutex, MutexGuard};

use crate::{
    Authentication, ConnectionProfile, CoreError, CoreEvent, DisconnectReason, MobileCore,
    SshTransport,
};

/// The entire portable core exposed to Swift and, later, Kotlin.
///
/// UniFFI sees one small synchronous Interface. Network work remains on the
/// SshTransport worker and events are drained by the native UI on its cadence.
#[derive(uniffi::Object)]
pub struct HerdieCore {
    inner: Mutex<MobileCore>,
}

#[uniffi::export]
impl HerdieCore {
    #[uniffi::constructor]
    pub fn new() -> Arc<Self> {
        Arc::new(Self {
            inner: Mutex::new(MobileCore::with_transport(Box::new(SshTransport::new()))),
        })
    }

    pub fn connect(
        &self,
        profile: ConnectionProfile,
        authentication: Authentication,
        expected_host_key: Option<String>,
        columns: u16,
        rows: u16,
    ) -> Result<(), CoreError> {
        self.core()
            .connect(profile, authentication, expected_host_key, columns, rows)
    }

    pub fn send(&self, input: Vec<u8>) -> Result<(), CoreError> {
        self.core().send(input)
    }

    pub fn resize(&self, columns: u16, rows: u16) -> Result<(), CoreError> {
        self.core().resize(columns, rows)
    }

    pub fn scroll(&self, lines: i32) -> Result<(), CoreError> {
        self.core().scroll(lines)
    }

    pub fn poll_events(&self) -> Vec<CoreEvent> {
        self.core().poll_events()
    }

    pub fn disconnect(&self, reason: DisconnectReason) {
        self.core().disconnect(reason);
    }
}

impl HerdieCore {
    fn core(&self) -> MutexGuard<'_, MobileCore> {
        self.inner
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }
}
