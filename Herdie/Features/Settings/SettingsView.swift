import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var preferences: AppPreferences

    var body: some View {
        NavigationStack {
            List {
                Section("Appearance") {
                    Picker("Theme", selection: $preferences.appearance) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Text(appearance.title).tag(appearance)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Terminal") {
                    NavigationLink {
                        ComposerSettingsView(preferences: preferences)
                    } label: {
                        SettingsRow(
                            title: "Composer",
                            subtitle: "Direct typing and multiline send",
                            symbol: "bubble.left"
                        )
                    }
                    .accessibilityLabel("Composer")

                    NavigationLink {
                        ToolbarSettingsView(preferences: preferences)
                    } label: {
                        SettingsRow(
                            title: "Toolbar",
                            subtitle: "Reorder and hide terminal actions",
                            symbol: "rectangle.bottomthird.inset.filled"
                        )
                    }
                    .accessibilityLabel("Toolbar")
                }

                Section("Connection") {
                    NavigationLink {
                        SecuritySettingsView()
                    } label: {
                        SettingsRow(
                            title: "Security",
                            subtitle: "Keychain and host-key verification",
                            symbol: "lock.shield"
                        )
                    }
                    HStack(spacing: 14) {
                        Image(systemName: "bell.badge")
                            .foregroundStyle(HerdieTheme.secondary)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Agent Hooks")
                            Text("Planned after the SSH-only release")
                                .font(.caption)
                                .foregroundStyle(HerdieTheme.secondary)
                        }
                        Spacer()
                        Text("Later")
                            .font(.caption)
                            .foregroundStyle(HerdieTheme.secondary)
                    }
                }

                Section("Herdie") {
                    NavigationLink {
                        AboutView()
                    } label: {
                        SettingsRow(
                            title: "Made by Lucas Scariot",
                            subtitle: "Meet the maker · About Herdie",
                            symbol: "person.crop.circle"
                        )
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(HerdieTheme.background)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(preferences.appearance.colorScheme)
    }
}

private struct SettingsRow: View {
    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .foregroundStyle(HerdieTheme.accent)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(HerdieTheme.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ComposerSettingsView: View {
    @Bindable var preferences: AppPreferences

    var body: some View {
        List {
            Section("Options") {
                Toggle(isOn: $preferences.composerMode) {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Composer Mode")
                            Text("Compose in a text box instead of typing directly into the terminal")
                                .font(.caption)
                                .foregroundStyle(HerdieTheme.secondary)
                        }
                    } icon: {
                        Image(systemName: "bubble.left")
                    }
                }
                .accessibilityLabel("Composer mode")

                Toggle(isOn: $preferences.autoSend) {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Auto Send")
                            Text("Send after dictation inserts a final newline")
                                .font(.caption)
                                .foregroundStyle(HerdieTheme.secondary)
                        }
                    } icon: {
                        Image(systemName: "paperplane")
                    }
                }
                .accessibilityLabel("Auto send")
            }

            Section {
                Text("Terminal and composer text travels only through your direct encrypted SSH session. Herdie has no transcript service.")
                    .font(.footnote)
                    .foregroundStyle(HerdieTheme.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(HerdieTheme.background)
        .navigationTitle("Composer")
    }
}

struct ToolbarSettingsView: View {
    @Bindable var preferences: AppPreferences

    private var availableActions: [ToolbarAction] {
        ToolbarAction.allCases.filter { !preferences.toolbarActions.contains($0) }
    }

    var body: some View {
        List {
            Section("Preview") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(preferences.toolbarActions) { action in
                            toolbarPreview(action)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }

            Section("Toolbar Buttons") {
                ForEach(preferences.toolbarActions) { action in
                    Label(action.title, systemImage: action.systemImage ?? "command")
                        .font(action.systemImage == nil ? .system(.body, design: .monospaced) : .body)
                }
                .onDelete { offsets in
                    preferences.toolbarActions.remove(atOffsets: offsets)
                }
                .onMove { offsets, destination in
                    preferences.toolbarActions.move(fromOffsets: offsets, toOffset: destination)
                }
            }

            if !availableActions.isEmpty {
                Section {
                    Menu {
                        ForEach(availableActions) { action in
                            Button(action.title, systemImage: action.systemImage ?? "command") {
                                preferences.toolbarActions.append(action)
                            }
                        }
                    } label: {
                        Label("Add Button", systemImage: "plus.circle")
                    }
                }
            }

            Section {
                Button("Reset Toolbar", systemImage: "arrow.counterclockwise") {
                    preferences.resetToolbar()
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        .scrollContentBackground(.hidden)
        .background(HerdieTheme.background)
        .navigationTitle("Toolbar")
    }

    private func toolbarPreview(_ action: ToolbarAction) -> some View {
        Group {
            if let symbol = action.systemImage {
                Image(systemName: symbol)
            } else {
                Text(action.title)
                    .font(.system(.subheadline, design: .monospaced))
            }
        }
        .frame(minWidth: 44, minHeight: 42)
        .padding(.horizontal, action.systemImage == nil ? 5 : 0)
        .background(HerdieTheme.raisedSurface, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct SecuritySettingsView: View {
    var body: some View {
        List {
            Section("On Device") {
                SecurityFact(
                    symbol: "key.fill",
                    title: "Credentials",
                    detail: "Passwords, private keys, and passphrases use iOS Keychain with this-device-only protection."
                )
                SecurityFact(
                    symbol: "checkmark.shield.fill",
                    title: "Host identity",
                    detail: "Unknown hosts require approval. A changed SHA-256 host key is blocked and shown as a mismatch."
                )
            }
            Section("Network") {
                SecurityFact(
                    symbol: "arrow.left.arrow.right",
                    title: "Direct SSH",
                    detail: "Herdie connects from this device to your host. There is no Herdie relay, analytics SDK, or account service."
                )
                SecurityFact(
                    symbol: "pause.circle",
                    title: "Backgrounding",
                    detail: "iOS may close the mobile connection. Herdie never sends a command that stops the remote Herdr server or its agents."
                )
            }
        }
        .scrollContentBackground(.hidden)
        .background(HerdieTheme.background)
        .navigationTitle("Security")
    }
}

private struct SecurityFact: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .foregroundStyle(HerdieTheme.accent)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(HerdieTheme.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct AboutView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var support = SupportConfiguration()

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image("HerdieLogo")
                    .resizable()
                    .frame(width: 112, height: 112)
                    .clipShape(RoundedRectangle(cornerRadius: 28))
                    .accessibilityHidden(true)
                VStack(spacing: 5) {
                    Text("Herdie")
                        .font(.largeTitle.bold())
                    Text("Version 0.1.0")
                        .foregroundStyle(HerdieTheme.secondary)
                }
                Text("An independent, open-source Herdr client built with SwiftUI and a portable Rust SSH core.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(HerdieTheme.secondary)
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Text("LS")
                            .font(.headline)
                            .foregroundStyle(HerdieTheme.onAccent)
                            .frame(width: 44, height: 44)
                            .background(HerdieTheme.accent.gradient, in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Made by Lucas Scariot")
                                .font(.headline)
                            Text("Independent maker")
                                .font(.subheadline)
                                .foregroundStyle(HerdieTheme.secondary)
                        }
                    }
                    Text("I build tools like Herdie. Follow what I’m working on, explore my other projects, or say hello.")
                        .font(.subheadline)
                        .foregroundStyle(HerdieTheme.secondary)
                    makerLink("Explore my work", detail: "lucas.scariot.fr", symbol: "globe", url: "https://lucas.scariot.fr/?utm_source=herdie&utm_medium=app&utm_campaign=maker")
                    makerLink("Follow on X", detail: "@lucas_scrt", symbol: "bubble.left.and.bubble.right", url: "https://x.com/lucas_scrt")
                    if support.isEnabled {
                        makerLink("Buy me a coffee", detail: "Optional support. Herdie stays free.", symbol: "cup.and.saucer", url: "https://buymeacoffee.com/lucasscariot")
                    }
                }
                .padding(18)
                .herdieCard()
                VStack(alignment: .leading, spacing: 12) {
                    Label("MIT licensed", systemImage: "chevron.left.forwardslash.chevron.right")
                    Label("No account required", systemImage: "person.crop.circle.badge.xmark")
                    Label("No telemetry", systemImage: "chart.bar.xaxis")
                    Label("Credentials stay in Keychain", systemImage: "key.fill")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .herdieCard()
                Text("Herdie interoperates with an installed Herdr binary and does not bundle Herdr source.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(HerdieTheme.secondary)
            }
            .padding(24)
        }
        .background(HerdieTheme.background)
        .navigationTitle("About")
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await support.refresh()
                do { try await Task.sleep(for: .seconds(60)) }
                catch { return }
            }
        }
    }

    private func makerLink(_ title: String, detail: String, symbol: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(detail).font(.caption).foregroundStyle(HerdieTheme.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.caption)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityHint("Opens in your browser")
    }
}
