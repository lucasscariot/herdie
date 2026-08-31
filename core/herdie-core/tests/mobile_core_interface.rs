use std::collections::VecDeque;
use std::sync::{Arc, Mutex};

use herdie_core::{
    Authentication, ConnectionProfile, CoreEventKind, DisconnectReason, MobileCore, SessionState,
    TransportAdapter, TransportCommand, TransportEvent, TransportRequest,
};

#[derive(Default)]
struct RecordingState {
    commands: Vec<TransportCommand>,
    events: VecDeque<TransportEvent>,
    open_error: Option<String>,
}

struct RecordingTransport {
    state: Arc<Mutex<RecordingState>>,
}

impl TransportAdapter for RecordingTransport {
    fn open(&mut self, request: TransportRequest) -> Result<(), String> {
        let mut state = self.state.lock().expect("recording state");
        state.commands.push(TransportCommand::Open(request));
        match &state.open_error {
            Some(message) => Err(message.clone()),
            None => Ok(()),
        }
    }

    fn send(&mut self, input: Vec<u8>) -> Result<(), String> {
        self.state
            .lock()
            .expect("recording state")
            .commands
            .push(TransportCommand::Send(input));
        Ok(())
    }

    fn resize(&mut self, columns: u16, rows: u16) -> Result<(), String> {
        self.state
            .lock()
            .expect("recording state")
            .commands
            .push(TransportCommand::Resize { columns, rows });
        Ok(())
    }

    fn close(&mut self) {
        self.state
            .lock()
            .expect("recording state")
            .commands
            .push(TransportCommand::Close);
    }

    fn poll(&mut self) -> Vec<TransportEvent> {
        self.state
            .lock()
            .expect("recording state")
            .events
            .drain(..)
            .collect()
    }
}

fn profile() -> ConnectionProfile {
    ConnectionProfile::new(
        "studio".into(),
        "Mac Studio".into(),
        "studio.local".into(),
        22,
        "lucas".into(),
    )
    .expect("profile")
}

fn core() -> (MobileCore, Arc<Mutex<RecordingState>>) {
    let state = Arc::new(Mutex::new(RecordingState::default()));
    let transport = RecordingTransport {
        state: Arc::clone(&state),
    };
    (MobileCore::with_transport(Box::new(transport)), state)
}

#[test]
fn connect_uses_one_transport_request_and_reports_connecting() {
    let (mut core, state) = core();

    core.connect(
        profile(),
        Authentication::Password {
            secret: "do-not-log".into(),
        },
        Some("SHA256:known".into()),
        100,
        30,
    )
    .expect("connect starts");

    {
        let recording = state.lock().expect("state");
        assert_eq!(recording.commands.len(), 1);
        let TransportCommand::Open(request) = &recording.commands[0] else {
            panic!("expected open")
        };
        assert_eq!(request.profile.host, "studio.local");
        assert_eq!(request.expected_host_key.as_deref(), Some("SHA256:known"));
        assert_eq!(request.columns, 100);
        assert_eq!(request.rows, 30);
    }

    let events = core.poll_events();
    assert_eq!(events[0].kind, CoreEventKind::StateChanged);
    assert_eq!(events[0].state, Some(SessionState::Connecting));
}

#[test]
fn repeated_connect_does_not_open_a_second_transport() {
    let (mut core, state) = core();
    core.connect(profile(), Authentication::None, None, 80, 24)
        .expect("first connect starts");

    core.connect(profile(), Authentication::None, None, 100, 30)
        .expect("repeated connect is idempotent");

    let open_count = state
        .lock()
        .expect("state")
        .commands
        .iter()
        .filter(|command| matches!(command, TransportCommand::Open(_)))
        .count();
    assert_eq!(open_count, 1);
}

#[test]
fn connection_profiles_are_revalidated_at_the_mobile_interface() {
    let (mut core, state) = core();
    let mut invalid_profile = profile();
    invalid_profile.host = "   ".into();

    let error = core
        .connect(invalid_profile, Authentication::None, None, 80, 24)
        .expect_err("invalid profile must be rejected");

    assert!(error.to_string().contains("host"));
    assert!(state.lock().expect("state").commands.is_empty());
    assert!(core.poll_events().is_empty());
}

#[test]
fn transport_data_becomes_a_batched_terminal_frame() {
    let (mut core, state) = core();
    core.connect(profile(), Authentication::None, None, 20, 4)
        .expect("connect starts");
    core.poll_events();
    state.lock().expect("state").events.extend([
        TransportEvent::Data(b"Her".to_vec()),
        TransportEvent::Connected,
        TransportEvent::Data(b"die".to_vec()),
    ]);

    let events = core.poll_events();

    assert_eq!(events[0].state, Some(SessionState::Attached));
    assert_eq!(
        events
            .iter()
            .filter(|event| event.kind == CoreEventKind::TerminalFrame)
            .count(),
        1
    );
    assert_eq!(events[1].kind, CoreEventKind::TerminalFrame);
    let snapshot = events[1]
        .terminal_snapshot_json
        .as_deref()
        .expect("terminal snapshot");
    assert!(snapshot.contains("Herdie"));
}

#[test]
fn input_and_resize_cross_the_same_small_interface() {
    let (mut core, state) = core();
    core.connect(profile(), Authentication::None, None, 80, 24)
        .expect("connect starts");

    core.send(b"hello\n".to_vec()).expect("send");
    core.resize(120, 40).expect("resize");

    let commands = &state.lock().expect("state").commands;
    assert_eq!(commands[1], TransportCommand::Send(b"hello\n".to_vec()));
    assert_eq!(
        commands[2],
        TransportCommand::Resize {
            columns: 120,
            rows: 40
        }
    );
}

#[test]
fn suspension_closes_only_the_mobile_transport() {
    let (mut core, state) = core();
    core.connect(profile(), Authentication::None, None, 80, 24)
        .expect("connect starts");

    core.disconnect(DisconnectReason::AppSuspended);

    let commands = &state.lock().expect("state").commands;
    assert_eq!(commands.last(), Some(&TransportCommand::Close));
    assert!(!commands.contains(&TransportCommand::StopRemoteHerdr));
}

#[test]
fn authentication_debug_output_is_redacted() {
    let authentication = Authentication::PrivateKey {
        key: "PRIVATE MATERIAL".into(),
        passphrase: Some("PASSPHRASE".into()),
    };

    let debug = format!("{authentication:?}");

    assert!(!debug.contains("PRIVATE MATERIAL"));
    assert!(!debug.contains("PASSPHRASE"));
    assert!(debug.contains("redacted"));
}

#[test]
fn synchronous_open_failure_does_not_leave_the_core_connecting() {
    let (mut core, state) = core();
    state.lock().expect("state").open_error = Some("worker unavailable".into());

    let error = core
        .connect(profile(), Authentication::None, None, 80, 24)
        .expect_err("open should fail");

    assert!(error.to_string().contains("worker unavailable"));
    let events = core.poll_events();
    assert_eq!(
        events.last().and_then(|event| event.state),
        Some(SessionState::Idle)
    );
}

#[test]
fn rejected_host_key_returns_to_idle_for_an_explicit_user_decision() {
    let (mut core, state) = core();
    core.connect(profile(), Authentication::None, None, 80, 24)
        .expect("connect starts");
    core.poll_events();
    state
        .lock()
        .expect("state")
        .events
        .push_back(TransportEvent::HostKeyUnknown {
            presented: "SHA256:new".into(),
        });

    let events = core.poll_events();

    assert_eq!(events[0].kind, CoreEventKind::HostKeyUnknown);
    assert_eq!(events[0].presented_host_key.as_deref(), Some("SHA256:new"));
    assert_eq!(
        events.last().and_then(|event| event.state),
        Some(SessionState::Idle)
    );
}

#[test]
fn asynchronous_connect_failure_returns_to_idle() {
    let (mut core, state) = core();
    core.connect(profile(), Authentication::None, None, 80, 24)
        .expect("connect starts");
    core.poll_events();
    state
        .lock()
        .expect("state")
        .events
        .push_back(TransportEvent::Failed {
            message: "authentication rejected".into(),
        });

    let events = core.poll_events();

    assert_eq!(events[0].kind, CoreEventKind::Error);
    assert_eq!(
        events.last().and_then(|event| event.state),
        Some(SessionState::Idle)
    );
}

#[test]
fn transport_failure_after_attachment_enters_reconnecting() {
    let (mut core, state) = core();
    core.connect(profile(), Authentication::None, None, 80, 24)
        .expect("connect starts");
    core.poll_events();
    state.lock().expect("state").events.extend([
        TransportEvent::Connected,
        TransportEvent::Failed {
            message: "connection lost".into(),
        },
    ]);

    let events = core.poll_events();

    assert_eq!(events[0].state, Some(SessionState::Attached));
    assert_eq!(events[1].kind, CoreEventKind::Error);
    assert_eq!(events[2].state, Some(SessionState::Reconnecting));
}

#[test]
fn failed_reconnect_attempt_preserves_reconnect_context() {
    let (mut core, state) = core();
    core.connect(profile(), Authentication::None, None, 80, 24)
        .expect("connect starts");
    core.poll_events();
    state.lock().expect("state").events.extend([
        TransportEvent::Connected,
        TransportEvent::Failed {
            message: "connection lost".into(),
        },
    ]);
    core.poll_events();

    core.connect(profile(), Authentication::None, None, 80, 24)
        .expect("reconnect starts");
    core.poll_events();
    state
        .lock()
        .expect("state")
        .events
        .push_back(TransportEvent::Failed {
            message: "host still unreachable".into(),
        });

    let events = core.poll_events();

    assert_eq!(
        events.last().and_then(|event| event.state),
        Some(SessionState::Reconnecting)
    );
}

#[test]
fn remote_command_exit_returns_to_idle_without_reconnecting() {
    let (mut core, state) = core();
    core.connect(profile(), Authentication::None, None, 80, 24)
        .expect("connect starts");
    core.poll_events();
    state.lock().expect("state").events.extend([
        TransportEvent::Connected,
        TransportEvent::RemoteExited {
            message: "Herdr exited with status 127".into(),
        },
    ]);

    let events = core.poll_events();

    assert_eq!(events[1].kind, CoreEventKind::Error);
    assert_eq!(
        events.last().and_then(|event| event.state),
        Some(SessionState::Idle)
    );
}
