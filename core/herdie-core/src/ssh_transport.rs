use std::future::Future;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{self, Receiver, SyncSender, TryRecvError};
use std::thread;
use std::time::Duration;

use russh::client;
use russh::keys::{HashAlg, PrivateKeyWithHashAlg, PublicKeyOrCertificate, decode_secret_key};
use russh::{Channel, ChannelMsg, Disconnect};
use tokio::sync::mpsc::{self as tokio_mpsc, UnboundedReceiver, UnboundedSender};

use crate::{
    Authentication, HostTrust, HostTrustDecision, TransportAdapter, TransportEvent,
    TransportRequest, agent,
};

const REMOTE_COMMAND: &str = r#"/bin/sh -c 'if command -v herdr >/dev/null 2>&1; then exec herdr; elif [ -x "$HOME/.local/bin/herdr" ]; then exec "$HOME/.local/bin/herdr"; elif [ -x /opt/homebrew/bin/herdr ]; then exec /opt/homebrew/bin/herdr; elif [ -x /usr/local/bin/herdr ]; then exec /usr/local/bin/herdr; else printf "Herdie: herdr executable not found\n" >&2; exit 127; fi'"#;
const TERMINAL_TYPE: &str = "xterm-256color";
const EVENT_CHANNEL_CAPACITY: usize = 256;
const MAX_POLL_EVENTS: usize = 128;
const MAX_POLL_DATA_BYTES: usize = 256 * 1024;

#[derive(Debug)]
enum Control {
    Send(Vec<u8>),
    Resize { columns: u16, rows: u16 },
    ListAgents,
    FocusAgent { command: String },
    Close,
}

/// Production SSH Adapter. Its Tokio runtime lives on a dedicated worker so the
/// synchronous mobile Interface never owns an executor or blocks a UI thread.
pub struct SshTransport {
    control: Option<UnboundedSender<Control>>,
    events: Option<Receiver<TransportEvent>>,
}

impl SshTransport {
    pub fn new() -> Self {
        Self {
            control: None,
            events: None,
        }
    }
}

impl Default for SshTransport {
    fn default() -> Self {
        Self::new()
    }
}

impl TransportAdapter for SshTransport {
    fn open(&mut self, request: TransportRequest) -> Result<(), String> {
        self.close();

        let (control_tx, control_rx) = tokio_mpsc::unbounded_channel();
        let (event_tx, event_rx) = mpsc::sync_channel(EVENT_CHANNEL_CAPACITY);
        let rejected_host_key = Arc::new(AtomicBool::new(false));
        let worker_rejected_host_key = Arc::clone(&rejected_host_key);

        thread::Builder::new()
            .name("herdie-ssh".into())
            .spawn(move || {
                let runtime = match tokio::runtime::Builder::new_multi_thread()
                    .worker_threads(1)
                    .enable_all()
                    .build()
                {
                    Ok(runtime) => runtime,
                    Err(error) => {
                        send_event(
                            &event_tx,
                            TransportEvent::Failed {
                                message: format!("failed to start SSH runtime: {error}"),
                            },
                        );
                        return;
                    }
                };

                match runtime.block_on(run_session(
                    request,
                    control_rx,
                    event_tx.clone(),
                    worker_rejected_host_key,
                )) {
                    Ok(Some(message)) => {
                        send_event(&event_tx, TransportEvent::RemoteExited { message });
                    }
                    Ok(None) => send_event(&event_tx, TransportEvent::Closed),
                    Err(message) if !rejected_host_key.load(Ordering::Acquire) => {
                        send_event(&event_tx, TransportEvent::Failed { message });
                    }
                    Err(_) => {}
                }
            })
            .map_err(|error| format!("failed to start SSH worker: {error}"))?;

        self.control = Some(control_tx);
        self.events = Some(event_rx);
        Ok(())
    }

    fn send(&mut self, input: Vec<u8>) -> Result<(), String> {
        self.send_control(Control::Send(input))
    }

    fn resize(&mut self, columns: u16, rows: u16) -> Result<(), String> {
        self.send_control(Control::Resize { columns, rows })
    }

    fn list_agents(&mut self) -> Result<(), String> {
        self.send_control(Control::ListAgents)
    }

    fn focus_agent(&mut self, pane_id: String) -> Result<(), String> {
        let command = agent::focus_command(&pane_id)?;
        self.send_control(Control::FocusAgent { command })
    }

    fn close(&mut self) {
        if let Some(control) = self.control.take() {
            let _ = control.send(Control::Close);
        }
        // A caller-requested close has already produced the authoritative state
        // transition in MobileCore, so discard any late worker events.
        self.events = None;
    }

    fn poll(&mut self) -> Vec<TransportEvent> {
        let Some(events) = self.events.as_ref() else {
            return Vec::new();
        };
        let mut batch = Vec::with_capacity(MAX_POLL_EVENTS);
        let mut data_bytes = 0;
        while batch.len() < MAX_POLL_EVENTS && data_bytes < MAX_POLL_DATA_BYTES {
            match events.try_recv() {
                Ok(event) => {
                    if let TransportEvent::Data(bytes) = &event {
                        data_bytes += bytes.len();
                    }
                    batch.push(event);
                }
                Err(TryRecvError::Empty | TryRecvError::Disconnected) => break,
            }
        }
        batch
    }
}

impl SshTransport {
    fn send_control(&self, control: Control) -> Result<(), String> {
        self.control
            .as_ref()
            .ok_or_else(|| "SSH session is not running".to_string())?
            .send(control)
            .map_err(|_| "SSH session is no longer available".to_string())
    }
}

impl Drop for SshTransport {
    fn drop(&mut self) {
        self.close();
    }
}

struct ClientHandler {
    expected_host_key: Option<String>,
    events: SyncSender<TransportEvent>,
    rejected_host_key: Arc<AtomicBool>,
}

impl client::Handler for ClientHandler {
    type Error = russh::Error;

    async fn check_server_key(
        &mut self,
        server_public_key: &PublicKeyOrCertificate,
    ) -> Result<bool, Self::Error> {
        let presented = server_public_key
            .public_key()
            .fingerprint(HashAlg::Sha256)
            .to_string();

        let event = match HostTrust::verify(self.expected_host_key.as_deref(), &presented) {
            HostTrustDecision::Trusted => return Ok(true),
            HostTrustDecision::Unknown { presented } => {
                TransportEvent::HostKeyUnknown { presented }
            }
            HostTrustDecision::Mismatch {
                expected,
                presented,
            } => TransportEvent::HostKeyMismatch {
                expected,
                presented,
            },
        };

        self.rejected_host_key.store(true, Ordering::Release);
        send_event(&self.events, event);
        Ok(false)
    }
}

async fn run_session(
    request: TransportRequest,
    mut control_rx: UnboundedReceiver<Control>,
    events: SyncSender<TransportEvent>,
    rejected_host_key: Arc<AtomicBool>,
) -> Result<Option<String>, String> {
    let mut pending_resize = None;
    let setup = establish_session(request, events.clone(), rejected_host_key);
    let (session, mut channel) =
        match await_setup(setup, &mut control_rx, &mut pending_resize).await {
            SetupOutcome::Ready(result) => result?,
            SetupOutcome::Cancelled => return Ok(None),
        };

    if let Some((columns, rows)) = pending_resize {
        channel
            .window_change(u32::from(columns), u32::from(rows), 0, 0)
            .await
            .map_err(|error| format!("failed to resize remote terminal: {error}"))?;
    }
    send_event(&events, TransportEvent::Connected);

    loop {
        tokio::select! {
            control = control_rx.recv() => {
                match control {
                    Some(Control::Send(input)) => channel
                        .data_bytes(input)
                        .await
                        .map_err(|error| format!("failed to send terminal input: {error}"))?,
                    Some(Control::Resize { columns, rows }) => channel
                        .window_change(u32::from(columns), u32::from(rows), 0, 0)
                        .await
                        .map_err(|error| format!("failed to resize remote terminal: {error}"))?,
                    Some(Control::ListAgents) => {
                        let output = run_control_command(&session, &agent::list_command()).await;
                        match output.and_then(|bytes| agent::parse_list(&bytes)) {
                            Ok(agents) => send_event(&events, TransportEvent::AgentsListed(agents)),
                            Err(message) => send_event(&events, TransportEvent::ControlFailed { message }),
                        }
                    }
                    Some(Control::FocusAgent { command }) => {
                        if let Err(message) = run_control_command(&session, &command).await {
                            send_event(&events, TransportEvent::ControlFailed { message });
                        }
                    }
                    Some(Control::Close) | None => {
                        let _ = channel.eof().await;
                        let _ = session
                            .disconnect(Disconnect::ByApplication, "", "en")
                            .await;
                        return Ok(None);
                    }
                }
            }
            message = channel.wait() => {
                match message {
                    Some(ChannelMsg::Data { data }) | Some(ChannelMsg::ExtendedData { data, .. }) => {
                        send_event(&events, TransportEvent::Data(data.to_vec()));
                    }
                    Some(ChannelMsg::ExitStatus { exit_status }) => {
                        return Ok(Some(remote_exit_message(exit_status)));
                    }
                    Some(ChannelMsg::ExitSignal { signal_name, error_message, .. }) => {
                        let detail = if error_message.is_empty() {
                            format!("Herdr exited after signal {signal_name:?}")
                        } else {
                            format!("Herdr exited after signal {signal_name:?}: {error_message}")
                        };
                        return Ok(Some(detail));
                    }
                    Some(ChannelMsg::Close) | None => return Ok(None),
                    _ => {}
                }
            }
        }
    }
}

const MAX_CONTROL_OUTPUT_BYTES: usize = 1024 * 1024;

async fn run_control_command(
    session: &client::Handle<ClientHandler>,
    command: &str,
) -> Result<Vec<u8>, String> {
    let mut channel = session
        .channel_open_session()
        .await
        .map_err(|error| format!("failed to open Herdr control channel: {error}"))?;
    channel
        .exec(true, command)
        .await
        .map_err(|error| format!("failed to run Herdr control command: {error}"))?;

    let mut output = Vec::new();
    let mut error_output = Vec::new();
    let mut exit_status = None;
    while let Some(message) = channel.wait().await {
        match message {
            ChannelMsg::Data { data } => append_control_output(&mut output, &data)?,
            ChannelMsg::ExtendedData { data, .. } => {
                append_control_output(&mut error_output, &data)?;
            }
            ChannelMsg::ExitStatus {
                exit_status: status,
            } => exit_status = Some(status),
            ChannelMsg::Close => break,
            _ => {}
        }
    }

    match exit_status {
        Some(0) => Ok(output),
        Some(status) => {
            let detail = String::from_utf8_lossy(&error_output).trim().to_string();
            if detail.is_empty() {
                Err(format!("Herdr control command exited with status {status}"))
            } else {
                Err(detail)
            }
        }
        None => Err("Herdr control command ended without an exit status".into()),
    }
}

fn append_control_output(target: &mut Vec<u8>, data: &[u8]) -> Result<(), String> {
    if target.len().saturating_add(data.len()) > MAX_CONTROL_OUTPUT_BYTES {
        return Err("Herdr returned too much agent data".into());
    }
    target.extend_from_slice(data);
    Ok(())
}

async fn establish_session(
    request: TransportRequest,
    events: SyncSender<TransportEvent>,
    rejected_host_key: Arc<AtomicBool>,
) -> Result<(client::Handle<ClientHandler>, Channel<client::Msg>), String> {
    let TransportRequest {
        profile,
        authentication,
        expected_host_key,
        columns,
        rows,
    } = request;
    let config = Arc::new(client::Config {
        inactivity_timeout: Some(Duration::from_secs(60)),
        keepalive_interval: Some(Duration::from_secs(15)),
        keepalive_max: 3,
        nodelay: true,
        ..Default::default()
    });
    let handler = ClientHandler {
        expected_host_key,
        events,
        rejected_host_key,
    };

    let address = (profile.host.as_str(), profile.port);
    let mut session = client::connect(config, address, handler)
        .await
        .map_err(|error| format!("SSH connection failed: {error}"))?;

    authenticate(&mut session, profile.username, authentication).await?;

    let channel = session
        .channel_open_session()
        .await
        .map_err(|error| format!("failed to open SSH session channel: {error}"))?;
    channel
        .request_pty(
            false,
            TERMINAL_TYPE,
            u32::from(columns),
            u32::from(rows),
            0,
            0,
            &[],
        )
        .await
        .map_err(|error| format!("failed to request remote terminal: {error}"))?;
    channel
        .exec(false, REMOTE_COMMAND)
        .await
        .map_err(|error| format!("failed to launch Herdr: {error}"))?;
    Ok((session, channel))
}

enum SetupOutcome<T> {
    Ready(T),
    Cancelled,
}

async fn await_setup<T>(
    setup: impl Future<Output = T>,
    control_rx: &mut UnboundedReceiver<Control>,
    pending_resize: &mut Option<(u16, u16)>,
) -> SetupOutcome<T> {
    tokio::pin!(setup);
    loop {
        tokio::select! {
            biased;
            control = control_rx.recv() => match control {
                Some(Control::Resize { columns, rows }) => {
                    *pending_resize = Some((columns, rows));
                }
                Some(Control::Send(_) | Control::ListAgents | Control::FocusAgent { .. }) => {}
                Some(Control::Close) | None => return SetupOutcome::Cancelled,
            },
            result = &mut setup => return SetupOutcome::Ready(result),
        }
    }
}

async fn authenticate<H: client::Handler>(
    session: &mut client::Handle<H>,
    username: String,
    authentication: Authentication,
) -> Result<(), String> {
    let result = match authentication {
        Authentication::None => session
            .authenticate_none(username)
            .await
            .map_err(|error| format!("SSH authentication failed: {error}"))?,
        Authentication::Password { secret } => session
            .authenticate_password(username, secret)
            .await
            .map_err(|error| format!("SSH authentication failed: {error}"))?,
        Authentication::PrivateKey { key, passphrase } => {
            let private_key = decode_secret_key(&key, passphrase.as_deref())
                .map_err(|error| format!("private key could not be decoded: {error}"))?;
            let hash_algorithm = session
                .best_supported_rsa_hash()
                .await
                .map_err(|error| format!("failed to negotiate public-key authentication: {error}"))?
                .flatten();
            session
                .authenticate_publickey(
                    username,
                    PrivateKeyWithHashAlg::new(Arc::new(private_key), hash_algorithm),
                )
                .await
                .map_err(|error| format!("SSH authentication failed: {error}"))?
        }
    };

    if result.success() {
        Ok(())
    } else {
        Err("SSH authentication was rejected by the host".into())
    }
}

fn send_event(events: &SyncSender<TransportEvent>, event: TransportEvent) {
    let _ = events.send(event);
}

fn remote_exit_message(exit_status: u32) -> String {
    if exit_status == 127 {
        "Herdr was not found on the remote host. Herdie checked PATH, ~/.local/bin, /opt/homebrew/bin, and /usr/local/bin."
            .into()
    } else {
        format!("Herdr exited with status {exit_status}")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test(flavor = "current_thread")]
    async fn close_cancels_an_in_flight_setup() {
        let (control_tx, mut control_rx) = tokio_mpsc::unbounded_channel();
        control_tx.send(Control::Close).expect("queue close");
        let mut pending_resize = None;

        let outcome = await_setup(
            std::future::pending::<()>(),
            &mut control_rx,
            &mut pending_resize,
        )
        .await;

        assert!(matches!(outcome, SetupOutcome::Cancelled));
    }

    #[tokio::test(flavor = "current_thread")]
    async fn latest_setup_resize_is_applied_after_connection() {
        let (control_tx, mut control_rx) = tokio_mpsc::unbounded_channel();
        control_tx
            .send(Control::Resize {
                columns: 100,
                rows: 30,
            })
            .expect("queue resize");
        control_tx
            .send(Control::Resize {
                columns: 120,
                rows: 40,
            })
            .expect("queue latest resize");
        let mut pending_resize = None;

        let outcome = await_setup(async { 7 }, &mut control_rx, &mut pending_resize).await;

        assert!(matches!(outcome, SetupOutcome::Ready(7)));
        assert_eq!(pending_resize, Some((120, 40)));
    }

    #[test]
    fn polling_is_bounded_even_when_the_producer_has_more_events() {
        let (event_tx, event_rx) = mpsc::sync_channel(EVENT_CHANNEL_CAPACITY);
        for _ in 0..(MAX_POLL_EVENTS + 1) {
            event_tx
                .try_send(TransportEvent::Data(vec![b'x']))
                .expect("queue output");
        }
        let mut transport = SshTransport {
            control: None,
            events: Some(event_rx),
        };

        assert_eq!(transport.poll().len(), MAX_POLL_EVENTS);
        assert_eq!(transport.poll().len(), 1);
    }

    #[test]
    fn polling_is_bounded_by_raw_output_size() {
        let (event_tx, event_rx) = mpsc::sync_channel(EVENT_CHANNEL_CAPACITY);
        for _ in 0..3 {
            event_tx
                .try_send(TransportEvent::Data(vec![b'x'; MAX_POLL_DATA_BYTES / 2]))
                .expect("queue output");
        }
        let mut transport = SshTransport {
            control: None,
            events: Some(event_rx),
        };

        assert_eq!(transport.poll().len(), 2);
        assert_eq!(transport.poll().len(), 1);
    }

    #[test]
    fn remote_command_falls_back_to_standard_herdr_install_locations() {
        assert!(REMOTE_COMMAND.starts_with("/bin/sh -c '"));
        assert!(REMOTE_COMMAND.ends_with('\''));
        assert!(!REMOTE_COMMAND.contains('\n'));
        assert!(REMOTE_COMMAND.contains("$HOME/.local/bin/herdr"));
        assert!(REMOTE_COMMAND.contains("/opt/homebrew/bin/herdr"));
        assert!(REMOTE_COMMAND.contains("/usr/local/bin/herdr"));
    }

    #[test]
    fn command_not_found_exit_explains_the_remote_install_requirement() {
        assert_eq!(
            remote_exit_message(127),
            "Herdr was not found on the remote host. Herdie checked PATH, ~/.local/bin, /opt/homebrew/bin, and /usr/local/bin."
        );
        assert_eq!(remote_exit_message(2), "Herdr exited with status 2");
    }
}
