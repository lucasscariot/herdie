use std::collections::VecDeque;
use std::fmt;

use serde::{Deserialize, Serialize};

use crate::{
    ConnectionProfile, CoreError, DisconnectReason, SessionAction, SessionMachine, SessionState,
    TerminalModel,
};

#[derive(Clone, PartialEq, Eq, uniffi::Enum)]
pub enum Authentication {
    None,
    Password {
        secret: String,
    },
    PrivateKey {
        key: String,
        passphrase: Option<String>,
    },
}

impl fmt::Debug for Authentication {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::None => formatter.write_str("None"),
            Self::Password { .. } => formatter.write_str("Password { secret: redacted }"),
            Self::PrivateKey { passphrase, .. } => formatter
                .debug_struct("PrivateKey")
                .field("key", &"redacted")
                .field("passphrase", &passphrase.as_ref().map(|_| "redacted"))
                .finish(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TransportRequest {
    pub profile: ConnectionProfile,
    pub authentication: Authentication,
    pub expected_host_key: Option<String>,
    pub columns: u16,
    pub rows: u16,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TransportCommand {
    Open(TransportRequest),
    Send(Vec<u8>),
    Resize { columns: u16, rows: u16 },
    Close,
    StopRemoteHerdr,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TransportEvent {
    Connected,
    HostKeyUnknown { presented: String },
    HostKeyMismatch { expected: String, presented: String },
    Data(Vec<u8>),
    Closed,
    RemoteExited { message: String },
    Failed { message: String },
}

pub trait TransportAdapter: Send {
    fn open(&mut self, request: TransportRequest) -> Result<(), String>;
    fn send(&mut self, input: Vec<u8>) -> Result<(), String>;
    fn resize(&mut self, columns: u16, rows: u16) -> Result<(), String>;
    fn close(&mut self);
    fn poll(&mut self) -> Vec<TransportEvent>;
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, uniffi::Enum)]
pub enum CoreEventKind {
    StateChanged,
    TerminalFrame,
    HostKeyUnknown,
    HostKeyMismatch,
    Error,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Record)]
pub struct CoreEvent {
    pub kind: CoreEventKind,
    pub state: Option<SessionState>,
    pub terminal_snapshot_json: Option<String>,
    pub message: Option<String>,
    pub expected_host_key: Option<String>,
    pub presented_host_key: Option<String>,
}

impl CoreEvent {
    fn state_changed(state: SessionState) -> Self {
        Self {
            kind: CoreEventKind::StateChanged,
            state: Some(state),
            terminal_snapshot_json: None,
            message: None,
            expected_host_key: None,
            presented_host_key: None,
        }
    }

    fn terminal_frame(snapshot: String) -> Self {
        Self {
            kind: CoreEventKind::TerminalFrame,
            state: None,
            terminal_snapshot_json: Some(snapshot),
            message: None,
            expected_host_key: None,
            presented_host_key: None,
        }
    }

    fn error(message: String) -> Self {
        Self {
            kind: CoreEventKind::Error,
            state: None,
            terminal_snapshot_json: None,
            message: Some(message),
            expected_host_key: None,
            presented_host_key: None,
        }
    }
}

pub struct MobileCore {
    machine: SessionMachine,
    terminal: TerminalModel,
    transport: Box<dyn TransportAdapter>,
    pending: VecDeque<CoreEvent>,
    reconnect_attempt: bool,
}

impl MobileCore {
    pub fn with_transport(transport: Box<dyn TransportAdapter>) -> Self {
        Self {
            machine: SessionMachine::new(),
            terminal: TerminalModel::new(80, 24, 10_000),
            transport,
            pending: VecDeque::new(),
            reconnect_attempt: false,
        }
    }

    pub fn connect(
        &mut self,
        profile: ConnectionProfile,
        authentication: Authentication,
        expected_host_key: Option<String>,
        columns: u16,
        rows: u16,
    ) -> Result<(), CoreError> {
        if columns == 0 || rows == 0 {
            return Err(CoreError::InvalidTerminalSize);
        }
        let profile = profile.validated()?;
        let reconnect_attempt = self.machine.state() == SessionState::Reconnecting;
        if self.machine.request_connect() != SessionAction::OpenTransport {
            return Ok(());
        }
        self.reconnect_attempt = reconnect_attempt;
        self.terminal.resize(columns, rows);
        self.pending
            .push_back(CoreEvent::state_changed(self.machine.state()));
        if let Err(message) = self.transport.open(TransportRequest {
            profile,
            authentication,
            expected_host_key,
            columns,
            rows,
        }) {
            let reason = if self.reconnect_attempt {
                DisconnectReason::NetworkLost
            } else {
                DisconnectReason::AuthenticationFailed
            };
            self.machine.disconnect(reason);
            self.pending
                .push_back(CoreEvent::state_changed(self.machine.state()));
            return Err(CoreError::Transport { message });
        }
        Ok(())
    }

    pub fn send(&mut self, input: Vec<u8>) -> Result<(), CoreError> {
        self.transport
            .send(input)
            .map_err(|message| CoreError::Transport { message })
    }

    pub fn resize(&mut self, columns: u16, rows: u16) -> Result<(), CoreError> {
        if columns == 0 || rows == 0 {
            return Err(CoreError::InvalidTerminalSize);
        }
        self.terminal.resize(columns, rows);
        self.transport
            .resize(columns, rows)
            .map_err(|message| CoreError::Transport { message })
    }

    pub fn scroll(&mut self, rows: u32) -> Result<(), CoreError> {
        self.terminal.scroll(rows);
        let snapshot = self.terminal.snapshot_json()?;
        self.pending.push_back(CoreEvent::terminal_frame(snapshot));
        Ok(())
    }

    pub fn poll_events(&mut self) -> Vec<CoreEvent> {
        let transport_events = self.transport.poll();
        let mut received_terminal_data = false;
        for event in transport_events {
            match event {
                TransportEvent::Data(bytes) => {
                    self.terminal.process(&bytes);
                    received_terminal_data = true;
                }
                event => self.consume_transport_event(event),
            }
        }
        if received_terminal_data {
            self.push_terminal_frame();
        }
        self.pending.drain(..).collect()
    }

    pub fn disconnect(&mut self, reason: DisconnectReason) {
        self.reconnect_attempt = false;
        self.machine.disconnect(reason);
        self.transport.close();
        self.pending
            .push_back(CoreEvent::state_changed(self.machine.state()));
    }

    fn consume_transport_event(&mut self, event: TransportEvent) {
        match event {
            TransportEvent::Connected => {
                self.reconnect_attempt = false;
                self.machine.did_connect();
                self.pending
                    .push_back(CoreEvent::state_changed(self.machine.state()));
            }
            TransportEvent::HostKeyUnknown { presented } => {
                self.reconnect_attempt = false;
                self.pending.push_back(CoreEvent {
                    kind: CoreEventKind::HostKeyUnknown,
                    state: None,
                    terminal_snapshot_json: None,
                    message: None,
                    expected_host_key: None,
                    presented_host_key: Some(presented),
                });
                self.machine.disconnect(DisconnectReason::HostKeyRejected);
                self.pending
                    .push_back(CoreEvent::state_changed(self.machine.state()));
            }
            TransportEvent::HostKeyMismatch {
                expected,
                presented,
            } => {
                self.reconnect_attempt = false;
                self.pending.push_back(CoreEvent {
                    kind: CoreEventKind::HostKeyMismatch,
                    state: None,
                    terminal_snapshot_json: None,
                    message: None,
                    expected_host_key: Some(expected),
                    presented_host_key: Some(presented),
                });
                self.machine.disconnect(DisconnectReason::HostKeyRejected);
                self.pending
                    .push_back(CoreEvent::state_changed(self.machine.state()));
            }
            TransportEvent::Data(bytes) => self.terminal.process(&bytes),
            TransportEvent::Closed => {
                self.reconnect_attempt = false;
                self.machine.disconnect(DisconnectReason::NetworkLost);
                self.pending
                    .push_back(CoreEvent::state_changed(self.machine.state()));
            }
            TransportEvent::RemoteExited { message } => {
                self.reconnect_attempt = false;
                self.pending.push_back(CoreEvent::error(message));
                self.machine.disconnect(DisconnectReason::RemoteExited);
                self.transport.close();
                self.pending
                    .push_back(CoreEvent::state_changed(self.machine.state()));
            }
            TransportEvent::Failed { message } => {
                self.pending.push_back(CoreEvent::error(message));
                let reason = match self.machine.state() {
                    SessionState::Connecting if !self.reconnect_attempt => {
                        DisconnectReason::AuthenticationFailed
                    }
                    SessionState::Connecting => DisconnectReason::NetworkLost,
                    SessionState::Attached | SessionState::Reconnecting | SessionState::Idle => {
                        DisconnectReason::NetworkLost
                    }
                };
                self.machine.disconnect(reason);
                self.transport.close();
                self.pending
                    .push_back(CoreEvent::state_changed(self.machine.state()));
            }
        }
    }

    fn push_terminal_frame(&mut self) {
        match self.terminal.snapshot_json() {
            Ok(snapshot) => self.pending.push_back(CoreEvent::terminal_frame(snapshot)),
            Err(error) => self.pending.push_back(CoreEvent::error(error.to_string())),
        }
    }
}
