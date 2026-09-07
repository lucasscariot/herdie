# Herdie

**Your Herdr sessions, on iPhone and iPad.**

Herdie is a free, open-source app for connecting to Herdr on your Mac or Linux host over SSH. Check on running agents, read terminal output, and send your next command. Your work continues on the host when you leave the app.

[Try the beta on TestFlight](https://testflight.apple.com/join/3Sn65RAt) · [Get help](https://github.com/lucasscariot/herdie/issues) · [Report a bug](https://github.com/lucasscariot/herdie/issues/new)

## Stay connected to your work

- **A terminal made for touch.** Read output behind floating controls, with a frosted header and room for your command line above the dock.
- **Switch between agents.** Open the agent picker to see running agents and jump to their terminal panes.
- **Write your way.** Use the keyboard for direct input or the writing sheet for longer messages. Keep a draft and return to it later.
- **Reconnect to your sessions.** Save your hosts and reattach to Herdr when you return to the app.
- **Make it comfortable.** Choose light or dark appearance, terminal colours, font size, and keyboard shortcuts.

## What you need

- An iPhone or iPad running iOS or iPadOS 18 or later.
- A Mac or Linux host with Herdr installed and SSH enabled.
- A network connection that lets your device reach that host.
- Your SSH hostname, port, username, and authentication details.

Herdie supports passwords, OpenSSH private keys, and SSH none authentication for compatible hosts such as Tailscale SSH. It does not provide a hosted computer, SSH account, or AI subscription.

## Get started

1. Install Herdie through TestFlight while the App Store release is being prepared.
2. Confirm that Herdr runs on your host and that SSH access is available.
3. Add your host in Herdie and choose its authentication method.
4. Verify the SSH host-key fingerprint against a trusted source, then connect.
5. Use **Agents** to switch panes, **Write** for a longer message, or **Keyboard** for direct terminal input.

## Your connection stays direct

Terminal traffic travels directly between your device and your SSH host. Saved passwords and private keys are stored in iOS Keychain. Herdie has no account service, terminal relay, or analytics SDK.

The About screen fetches a small public configuration file to decide whether to show an optional support link. That request does not include SSH credentials or terminal content. Websites opened from the app handle their own network requests and privacy practices.

## Help and feedback

[Open an issue](https://github.com/lucasscariot/herdie/issues) with your device model, iOS version, Herdie version, and steps to reproduce the problem. For connection issues, include the authentication method and a redacted error message.

Issues are public. Never include passwords, private keys, access tokens, or sensitive terminal output.

Herdie is made by Lucas Scariot. If it is useful to you, a star on this repository helps others find it. Contributions and bug reports are welcome.

## Development

Requirements:

- Xcode 26.3 or newer
- XcodeGen
- Rust 1.85 or newer (edition 2024)
- Rust targets `aarch64-apple-ios`, `aarch64-apple-ios-sim`,
  `x86_64-apple-ios`, and `aarch64-linux-android`

Generate the Xcode project and run checks:

```sh
make project
make test
make check-android
```

`make build-core-android` additionally builds the SSH-enabled Android library
and Kotlin bindings when `ANDROID_NDK_HOME` points to an installed Android NDK.

Herdie never stores credentials in project files or user defaults. The iOS app
stores secrets in Keychain and sends them directly to the selected host.

Before an App Store release, follow the [release checklist](docs/APP_STORE.md).

## License

MIT. Herdie is independently implemented and does not bundle Herdr source.
