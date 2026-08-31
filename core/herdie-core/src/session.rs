use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, uniffi::Enum)]
pub enum SessionState {
    Idle,
    Connecting,
    Attached,
    Reconnecting,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, uniffi::Enum)]
pub enum DisconnectReason {
    UserRequested,
    AppSuspended,
    NetworkLost,
    AuthenticationFailed,
    HostKeyRejected,
    RemoteExited,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, uniffi::Enum)]
pub enum SessionAction {
    None,
    OpenTransport,
    LaunchHerdr,
    CloseTransport,
    ScheduleReconnect,
    StopRemoteHerdr,
}

#[derive(Debug, Clone)]
pub struct SessionMachine {
    state: SessionState,
}

impl Default for SessionMachine {
    fn default() -> Self {
        Self::new()
    }
}

impl SessionMachine {
    pub fn new() -> Self {
        Self {
            state: SessionState::Idle,
        }
    }

    pub fn state(&self) -> SessionState {
        self.state
    }

    pub fn request_connect(&mut self) -> SessionAction {
        match self.state {
            SessionState::Idle | SessionState::Reconnecting => {
                self.state = SessionState::Connecting;
                SessionAction::OpenTransport
            }
            SessionState::Connecting | SessionState::Attached => SessionAction::None,
        }
    }

    pub fn did_connect(&mut self) -> SessionAction {
        if self.state == SessionState::Connecting {
            self.state = SessionState::Attached;
            SessionAction::LaunchHerdr
        } else {
            SessionAction::None
        }
    }

    pub fn disconnect(&mut self, reason: DisconnectReason) -> SessionAction {
        match reason {
            DisconnectReason::UserRequested => {
                self.state = SessionState::Idle;
                SessionAction::CloseTransport
            }
            DisconnectReason::AppSuspended => {
                self.state = SessionState::Reconnecting;
                SessionAction::CloseTransport
            }
            DisconnectReason::NetworkLost => {
                self.state = SessionState::Reconnecting;
                SessionAction::ScheduleReconnect
            }
            DisconnectReason::AuthenticationFailed
            | DisconnectReason::HostKeyRejected
            | DisconnectReason::RemoteExited => {
                self.state = SessionState::Idle;
                SessionAction::CloseTransport
            }
        }
    }

    pub fn retry(&mut self) -> SessionAction {
        self.request_connect()
    }
}
