# Architecture

## Module shape

Herdie has two large modules behind one narrow seam.

```text
SwiftUI application
  screens, rendering, Keychain, lifecycle
                |
       MobileCore interface
                |
Rust portable core
  SSH, host trust, PTY, terminal state, Herdr attach
```

The `MobileCore` interface contains connection lifecycle, input, resize, event
polling, and disconnection. It does not expose the SSH library, Tokio, terminal
parser, or Herdr command details. Swift and future Kotlin callers learn one
interface while the implementation can change internally.

## Native module

Swift owns behavior that is genuinely platform-specific:

- Keychain and biometric access
- SwiftUI navigation and sheets
- keyboard, dictation, clipboard, and hardware-key events
- app lifecycle and scene restoration
- terminal grid drawing and accessibility

`CredentialVault` is a real seam because production uses a Keychain adapter and
tests use an in-memory adapter. `SessionClient` is also real because production
uses the Rust adapter while tests and previews use an in-memory adapter.

## Portable core

Rust owns behavior that Android would otherwise duplicate:

- profile validation and connection state transitions
- host-key comparison
- SSH authentication and PTY lifecycle
- terminal parsing, resizing, snapshots, and scrollback
- Herdr launch and reconnect state policy
- event ordering and redaction

The core exposes batched events instead of per-cell callbacks. This keeps the
foreign-function interface small and prevents high-volume terminal output from
turning into thousands of cross-language calls.

The SSH adapter launches Herdr through a fixed, shell-safe discovery command.
It prefers the remote PATH, then checks `~/.local/bin`, Apple Silicon Homebrew,
and `/usr/local/bin`. Exit status 127 is surfaced as an install/path diagnostic
instead of a generic remote-process failure.

Agent discovery and focus reuse the authenticated SSH connection through short
control channels. The Rust core runs `herdr agent list`, maps the sidebar JSON
to portable records, and validates returned pane IDs before passing one to
`herdr agent focus`. Swift renders the records without parsing terminal output.

SSH output crosses a bounded producer channel. Each poll also has event and raw
byte budgets, and all data accepted in that poll produces at most one terminal
snapshot. This gives the remote TCP stream backpressure without letting one
busy terminal monopolize the main actor.

A transport loss retains reconnect context across failed attempts. Swift owns
the lifecycle timer and makes at most four delayed attempts (250 ms, 1 s, 2 s,
and 4 s). The budget resets only after five seconds of stable attachment, so a
rapid attach/drop loop remains bounded. A reported remote command exit returns
to idle instead of relaunching Herdr. Background suspension resets the retry
budget and never stops the remote Herdr process.

Connection metadata and Keychain credentials are separate stores. Credential
mutation happens first; if metadata persistence fails, the previous Keychain
value is restored before the error is surfaced. Deletion uses the same rollback
rule.

## Testing

Tests cross the same interfaces as production callers.

- Rust interface tests use an in-memory transport adapter.
- Rust parser tests feed recorded ANSI byte streams.
- Swift feature tests use an in-memory session adapter and credential vault.
- Keychain tests use a unique test-only service and delete their records.
- UI tests cover connection creation, saved-connection management, terminal
  preference navigation, and persistent connection-failure recovery. Feature
  tests cover reconnect, host trust, workspace key sequences, composer behavior,
  and toolbar input.

Live SSH checks are separate because they require a user-owned host and must not
become a condition for deterministic local tests.

## Licensing

Herdie is MIT-licensed and independently implemented. The app may invoke an
installed `herdr` binary and interoperate with documented command output, but it
does not copy, link, or redistribute Herdr source.
