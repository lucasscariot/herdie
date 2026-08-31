use herdie_core::{DisconnectReason, SessionAction, SessionMachine, SessionState};

#[test]
fn connects_through_explicit_states() {
    let mut machine = SessionMachine::new();

    assert_eq!(machine.state(), SessionState::Idle);
    assert_eq!(machine.request_connect(), SessionAction::OpenTransport);
    assert_eq!(machine.state(), SessionState::Connecting);
    assert_eq!(machine.did_connect(), SessionAction::LaunchHerdr);
    assert_eq!(machine.state(), SessionState::Attached);
}

#[test]
fn suspension_only_closes_the_local_transport() {
    let mut machine = SessionMachine::new();
    machine.request_connect();
    machine.did_connect();

    let action = machine.disconnect(DisconnectReason::AppSuspended);

    assert_eq!(action, SessionAction::CloseTransport);
    assert_eq!(machine.state(), SessionState::Reconnecting);
    assert_ne!(action, SessionAction::StopRemoteHerdr);
}

#[test]
fn an_unexpected_network_loss_schedules_reattach() {
    let mut machine = SessionMachine::new();
    machine.request_connect();
    machine.did_connect();

    assert_eq!(
        machine.disconnect(DisconnectReason::NetworkLost),
        SessionAction::ScheduleReconnect
    );
    assert_eq!(machine.state(), SessionState::Reconnecting);
    assert_eq!(machine.retry(), SessionAction::OpenTransport);
    assert_eq!(machine.state(), SessionState::Connecting);
}

#[test]
fn user_disconnect_does_not_stop_the_remote_session() {
    let mut machine = SessionMachine::new();
    machine.request_connect();
    machine.did_connect();

    assert_eq!(
        machine.disconnect(DisconnectReason::UserRequested),
        SessionAction::CloseTransport
    );
    assert_eq!(machine.state(), SessionState::Idle);
}
