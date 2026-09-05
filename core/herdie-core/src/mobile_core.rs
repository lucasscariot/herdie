use std::collections::VecDeque;
use std::fmt;

use serde::{Deserialize, Serialize};

use crate::{
    AgentSnapshot, ConnectionProfile, CoreError, DisconnectReason, SessionAction, SessionMachine,
    SessionState, TerminalModel, TerminalUpdate,
};

const LOCAL_SCROLLBACK_LINES: usize = 1_000;

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
    ListAgents,
    FocusAgent { pane_id: String },
    Close,
    StopRemoteHerdr,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TransportEvent {
    Connected,
    HostKeyUnknown { presented: String },
    HostKeyMismatch { expected: String, presented: String },
    Data(Vec<u8>),
    AgentsListed(Vec<AgentSnapshot>),
    ControlFailed { message: String },
    Closed,
    RemoteExited { message: String },
    Failed { message: String },
}

pub trait TransportAdapter: Send {
    fn open(&mut self, request: TransportRequest) -> Result<(), String>;
    fn send(&mut self, input: Vec<u8>) -> Result<(), String>;
    fn resize(&mut self, columns: u16, rows: u16) -> Result<(), String>;
    fn list_agents(&mut self) -> Result<(), String>;
    fn focus_agent(&mut self, pane_id: String) -> Result<(), String>;
    fn close(&mut self);
    fn poll(&mut self) -> Vec<TransportEvent>;
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, uniffi::Enum)]
pub enum CoreEventKind {
    StateChanged,
    TerminalFrame,
    HostKeyUnknown,
    HostKeyMismatch,
    AgentsUpdated,
    Error,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Record)]
pub struct CoreEvent {
    pub kind: CoreEventKind,
    pub state: Option<SessionState>,
    pub terminal_update: Option<TerminalUpdate>,
    pub message: Option<String>,
    pub expected_host_key: Option<String>,
    pub presented_host_key: Option<String>,
    pub agents: Option<Vec<AgentSnapshot>>,
}

impl CoreEvent {
    fn state_changed(state: SessionState) -> Self {
        Self {
            kind: CoreEventKind::StateChanged,
            state: Some(state),
            terminal_update: None,
            message: None,
            expected_host_key: None,
            presented_host_key: None,
            agents: None,
        }
    }

    fn terminal_frame(update: TerminalUpdate) -> Self {
        Self {
            kind: CoreEventKind::TerminalFrame,
            state: None,
            terminal_update: Some(update),
            message: None,
            expected_host_key: None,
            presented_host_key: None,
            agents: None,
        }
    }

    fn error(message: String) -> Self {
        Self {
            kind: CoreEventKind::Error,
            state: None,
            terminal_update: None,
            message: Some(message),
            expected_host_key: None,
            presented_host_key: None,
            agents: None,
        }
    }

    fn agents_updated(agents: Vec<AgentSnapshot>) -> Self {
        Self {
            kind: CoreEventKind::AgentsUpdated,
            state: None,
            terminal_update: None,
            message: None,
            expected_host_key: None,
            presented_host_key: None,
            agents: Some(agents),
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
            terminal: TerminalModel::new(80, 24, LOCAL_SCROLLBACK_LINES),
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

    pub fn scroll(&mut self, lines: i32) -> Result<(), CoreError> {
        let input = self.terminal.mouse_wheel_input(lines);
        if input.is_empty() {
            return Ok(());
        }
        self.transport
            .send(input)
            .map_err(|message| CoreError::Transport { message })
    }

    pub fn list_agents(&mut self) -> Result<(), CoreError> {
        self.transport
            .list_agents()
            .map_err(|message| CoreError::Transport { message })
    }

    pub fn focus_agent(&mut self, pane_id: String) -> Result<(), CoreError> {
        self.transport
            .focus_agent(pane_id)
            .map_err(|message| CoreError::Transport { message })
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
                    terminal_update: None,
                    message: None,
                    expected_host_key: None,
                    presented_host_key: Some(presented),
                    agents: None,
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
                    terminal_update: None,
                    message: None,
                    expected_host_key: Some(expected),
                    presented_host_key: Some(presented),
                    agents: None,
                });
                self.machine.disconnect(DisconnectReason::HostKeyRejected);
                self.pending
                    .push_back(CoreEvent::state_changed(self.machine.state()));
            }
            TransportEvent::Data(bytes) => self.terminal.process(&bytes),
            TransportEvent::AgentsListed(agents) => {
                self.pending.push_back(CoreEvent::agents_updated(agents));
            }
            TransportEvent::ControlFailed { message } => {
                self.pending.push_back(CoreEvent::error(message));
            }
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
        if let Some(update) = self.terminal.take_update() {
            self.pending.push_back(CoreEvent::terminal_frame(update));
        }
    }
}
