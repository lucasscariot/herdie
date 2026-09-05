# Herdie product specification

## Product contract

Herdie is an iPhone-first controller for persistent Herdr sessions. A user saves
an SSH connection, sees active work on the home screen, resumes a session with
one tap, and can leave the app without stopping remote agents.

The first release supports SSH only. Terminal traffic travels directly between
the device and the selected host. Herdie has no account system, relay, telemetry,
or hosted backend.

## First-release scope

### Connections

- Save a display name, host, port, and username.
- Authenticate with a password, an imported OpenSSH private key, or SSH none
  authentication for hosts such as Tailscale SSH.
- Store secrets in iOS Keychain and non-secret connection metadata on device.
- Require explicit trust for a new host key and reject changed host keys.
- Connect only after all required fields pass local validation.

### Home

- Show active and recent sessions before saved connections.
- Show a terminal preview, connection name, active workspace, transport, and
  aggregate Herdr state when known.
- Resume an active session from its card.
- Add, edit, reorder, and delete saved connections.
- Explain when Herdr is missing or an SSH connection cannot be reached.

### Terminal

- Open an interactive `xterm-256color` PTY and execute `herdr` on the host,
  discovering standard user-local and Homebrew install locations when the
  non-interactive SSH PATH does not include them.
- Render UTF-8 text, ANSI colours, text attributes, cursor state, and alternate
  screen applications.
- Send text, control keys, paste, and configurable toolbar actions.
- Resize the remote PTY when the visible grid changes.
- Preserve local scrollback and composer drafts across connection changes.
- Reconnect after foregrounding without stopping the remote Herdr server.

### Herdr navigation

- Present workspaces in a sheet above the current terminal.
- List the agents shown in Herdr's sidebar, including state and reported usage.
- Move the attached Herdr terminal to an agent by tapping its row.
- Mark the active workspace and show agent state when structured state exists.
- Switch workspaces without creating another saved connection.
- Fall back to the Herdr terminal interface when structured discovery is not
  supported by the installed Herdr version.

### Composer and toolbar

- Offer direct terminal typing and a multiline composer.
- Keep explicit send as the default for typed and dictated content.
- Provide Ctrl, Escape, Tab, Herdr prefix, navigation, paste, composer, and
  keyboard actions.
- Let the user reorder and hide toolbar actions.

## Deferred work

- Mosh and Eternal Terminal transports
- Parsed chat transcripts
- Push hooks, Live Activities, and notification relays
- Global search
- Generic tmux discovery
- Payments or free-use counters

## Security invariants

- Herdie never accepts an unknown or changed host key without user approval.
- Herdie never writes passwords or private keys to logs, user defaults, previews,
  crash metadata, or the repository.
- Deleting a connection removes its Keychain items.
- Terminal and composer content do not leave the SSH connection.
- Background suspension may end the network connection but must never send a
  remote stop, kill, logout, or server-shutdown command.

## Acceptance scenarios

1. A user adds a password connection, approves its host key, connects, and sees
   an interactive Herdr terminal.
2. A user backgrounds Herdie, returns after iOS suspended it, and reattaches to
   the same remote Herdr session.
3. A changed host key blocks connection and clearly identifies the mismatch.
4. A user sends Ctrl, Escape, Tab, the Herdr prefix, ordinary text, and pasted
   multiline text without corruption.
5. A user removes a saved connection and its corresponding credential can no
   longer be read from Keychain.
6. The Rust core builds for iOS device, iOS simulator, and Android ARM64 targets.
