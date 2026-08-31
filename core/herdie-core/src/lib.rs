//! Portable core for Herdie.

#[cfg(feature = "ssh")]
mod ffi;
mod mobile_core;
mod profile;
mod session;
#[cfg(feature = "ssh")]
mod ssh_transport;
mod terminal;
mod trust;

#[cfg(feature = "ssh")]
pub use ffi::HerdieCore;
pub use mobile_core::{
    Authentication, CoreEvent, CoreEventKind, MobileCore, TransportAdapter, TransportCommand,
    TransportEvent, TransportRequest,
};
pub use profile::{ConnectionProfile, CoreError};
pub use session::{DisconnectReason, SessionAction, SessionMachine, SessionState};
#[cfg(feature = "ssh")]
pub use ssh_transport::SshTransport;
pub use terminal::{
    AnsiColor, CellSnapshot, CursorSnapshot, TerminalModel, TerminalSnapshot, TerminalUpdate,
};
pub use trust::{HostTrust, HostTrustDecision};

uniffi::setup_scaffolding!();
