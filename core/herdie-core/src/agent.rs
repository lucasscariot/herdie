use serde::{Deserialize, Serialize};

#[cfg(any(feature = "ssh", test))]
const REMOTE_HERDR_PREFIX: &str = r#"/bin/sh -c 'if command -v herdr >/dev/null 2>&1; then exec herdr "$@"; elif [ -x "$HOME/.local/bin/herdr" ]; then exec "$HOME/.local/bin/herdr" "$@"; elif [ -x /opt/homebrew/bin/herdr ]; then exec /opt/homebrew/bin/herdr "$@"; elif [ -x /usr/local/bin/herdr ]; then exec /usr/local/bin/herdr "$@"; else printf "Herdie: herdr executable not found\n" >&2; exit 127; fi' herdr"#;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, uniffi::Enum)]
pub enum AgentStatus {
    Unknown,
    Idle,
    Working,
    Blocked,
    Done,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, uniffi::Record)]
pub struct AgentSnapshot {
    pub agent: String,
    pub status: AgentStatus,
    pub workspace_id: String,
    pub tab_id: String,
    pub pane_id: String,
    pub title: String,
    pub provider: Option<String>,
    pub context: Option<String>,
    pub limit: Option<String>,
    pub focused: bool,
}

#[cfg(feature = "ssh")]
pub(crate) fn list_command() -> String {
    format!("{REMOTE_HERDR_PREFIX} agent list")
}

#[cfg(any(feature = "ssh", test))]
pub(crate) fn focus_command(pane_id: &str) -> Result<String, String> {
    if !valid_pane_id(pane_id) {
        return Err("Herdr returned an invalid agent pane identifier".into());
    }
    Ok(format!("{REMOTE_HERDR_PREFIX} agent focus {pane_id}"))
}

#[cfg(any(feature = "ssh", test))]
pub(crate) fn parse_list(output: &[u8]) -> Result<Vec<AgentSnapshot>, String> {
    let envelope: AgentListEnvelope = serde_json::from_slice(output)
        .map_err(|error| format!("Herdr returned an unreadable agent list: {error}"))?;
    Ok(envelope.result.agents.into_iter().map(Into::into).collect())
}

#[cfg(any(feature = "ssh", test))]
#[derive(Deserialize)]
struct AgentListEnvelope {
    result: AgentListResult,
}

#[cfg(any(feature = "ssh", test))]
#[derive(Deserialize)]
struct AgentListResult {
    agents: Vec<RemoteAgent>,
}

#[cfg(any(feature = "ssh", test))]
#[derive(Deserialize)]
struct RemoteAgent {
    agent: String,
    agent_status: String,
    workspace_id: String,
    tab_id: String,
    pane_id: String,
    terminal_title_stripped: Option<String>,
    cwd: Option<String>,
    focused: bool,
    tokens: Option<RemoteAgentTokens>,
}

#[cfg(any(feature = "ssh", test))]
impl From<RemoteAgent> for AgentSnapshot {
    fn from(remote: RemoteAgent) -> Self {
        let tokens = remote.tokens;
        let title = tokens
            .as_ref()
            .and_then(|value| value.title.clone())
            .or(remote.terminal_title_stripped)
            .or_else(|| directory_name(remote.cwd.as_deref()))
            .unwrap_or_else(|| remote.agent.clone());
        Self {
            agent: remote.agent,
            status: AgentStatus::from_remote(&remote.agent_status),
            workspace_id: remote.workspace_id,
            tab_id: remote.tab_id,
            pane_id: remote.pane_id,
            title,
            provider: tokens.as_ref().and_then(|value| value.provider.clone()),
            context: tokens.as_ref().and_then(|value| value.context.clone()),
            limit: tokens.and_then(|value| value.limit),
            focused: remote.focused,
        }
    }
}

#[cfg(any(feature = "ssh", test))]
impl AgentStatus {
    fn from_remote(status: &str) -> Self {
        match status {
            "idle" => Self::Idle,
            "working" => Self::Working,
            "blocked" => Self::Blocked,
            "done" => Self::Done,
            _ => Self::Unknown,
        }
    }
}

#[cfg(any(feature = "ssh", test))]
#[derive(Deserialize)]
struct RemoteAgentTokens {
    title: Option<String>,
    provider: Option<String>,
    context: Option<String>,
    limit: Option<String>,
}

#[cfg(any(feature = "ssh", test))]
fn directory_name(path: Option<&str>) -> Option<String> {
    path.and_then(|value| value.rsplit('/').find(|part| !part.is_empty()))
        .map(str::to_string)
}

#[cfg(any(feature = "ssh", test))]
fn valid_pane_id(pane_id: &str) -> bool {
    !pane_id.is_empty()
        && pane_id.len() <= 64
        && pane_id
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b':' | b'_' | b'-'))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn agent_list_json_maps_sidebar_fields() {
        let output = br#"{"id":"cli:agent:list","result":{"agents":[{"agent":"codex","agent_status":"working","cwd":"/Users/lucas/herdr-ios","focused":true,"pane_id":"wE:p1","tab_id":"wE:t1","terminal_title_stripped":"herdr-ios","tokens":{"context":"50k","limit":"7d 79%","provider":"codex","title":"herdr-ios"},"workspace_id":"wE"}]}}"#;

        let agents = parse_list(output).expect("agent list parses");

        assert_eq!(agents.len(), 1);
        assert_eq!(agents[0].status, AgentStatus::Working);
        assert_eq!(agents[0].title, "herdr-ios");
        assert_eq!(agents[0].pane_id, "wE:p1");
        assert_eq!(agents[0].context.as_deref(), Some("50k"));
        assert_eq!(agents[0].limit.as_deref(), Some("7d 79%"));
        assert!(agents[0].focused);
    }

    #[test]
    fn title_falls_back_to_working_directory_then_agent_name() {
        let directory = br#"{"result":{"agents":[{"agent":"codex","agent_status":"idle","cwd":"/work/herdie/","focused":false,"pane_id":"p1","tab_id":"t1","terminal_title_stripped":null,"tokens":null,"workspace_id":"w1"}]}}"#;
        let agent_name = br#"{"result":{"agents":[{"agent":"claude","agent_status":"new","cwd":null,"focused":false,"pane_id":"p2","tab_id":"t1","terminal_title_stripped":null,"tokens":null,"workspace_id":"w1"}]}}"#;

        assert_eq!(
            parse_list(directory).expect("directory response parses")[0].title,
            "herdie"
        );
        let agents = parse_list(agent_name).expect("agent-name response parses");
        let agent = &agents[0];
        assert_eq!(agent.title, "claude");
        assert_eq!(agent.status, AgentStatus::Unknown);
    }

    #[test]
    fn focus_command_accepts_only_shell_safe_identifiers() {
        assert!(focus_command("wE:p1").is_ok());
        assert!(focus_command("review_agent-2").is_ok());
        assert!(focus_command("wE:p1; reboot").is_err());
        assert!(focus_command("").is_err());
    }
}
