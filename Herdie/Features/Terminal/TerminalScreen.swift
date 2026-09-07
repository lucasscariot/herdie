import SwiftUI
import UIKit

struct TerminalScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    let environment: AppEnvironment
    let onSessionEnded: (TerminalFrame) -> Void

    @State private var model: TerminalViewModel
    @State private var hasConnected = false
    @State private var showingWorkspaces = false
    @State private var showingAgents = false
    @State private var hasEnded = false
    @State private var showingReader = false
    @State private var readingSnapshot = ""
    @State private var readingURLs: Set<URL> = []
    @State private var showingWriting = false
    @State private var keyboardVisible = false
    @State private var focusMode = false
    @State private var dockCollapsed = false
    private var showsDock: Bool { !focusMode && (!keyboardVisible || showingWriting) }
    @State private var loadingVisible = false
    @State private var showingDetails = false
    @State private var submissionFeedback = 0
    private var terminalBackground: Color { Color(uiColor: environment.preferences.terminalTheme.background) }
    @State private var showingTerminalAppearance = false

    init(
        connection: SavedConnection,
        environment: AppEnvironment,
        onSessionEnded: @escaping (TerminalFrame) -> Void
    ) {
        self.environment = environment
        self.onSessionEnded = onSessionEnded
        _model = State(initialValue: TerminalViewModel(
            connection: connection,
            repository: environment.connectionRepository,
            credentialVault: environment.credentialVault,
            session: environment.makeSessionClient()
        ))
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                LiveTerminalCanvas(
                    model: model,
                    preferences: environment.preferences,
                    // Remote mouse-wheel scrolling does not update local scrollbackOffset.
                    // Release the prompt clearance while browsing behind the collapsed dock.
                    bottomClearance: keyboardVisible || dockCollapsed ? 0 : geometry.safeAreaInsets.bottom + (showsDock ? 76 : 0),
                    onScrollDirection: { rows in
                        if rows != 0 { dockCollapsed = rows > 0 }
                    },
                    onResize: handleResize,
                    onPaste: paste,
                    onFocusChanged: { focused in
                        keyboardVisible = focused
                        if focused { dockCollapsed = false }
                    }
                )
                // Extend only the canvas. Controls stay inside the safe area,
                // and the keyboard still reduces the terminal's available height.
                .padding(.horizontal, 12)
                .ignoresSafeArea(.container, edges: .vertical)
            }
                .accessibilityIdentifier("terminal-canvas")
                .opacity(model.hasAttached || !loadingVisible ? 1 : 0)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: model.hasAttached)
                .overlay(alignment: model.hasAttached ? .top : .center) {
                    if showsConnectionRecovery {
                        ScrollView {
                            connectionOverlay
                                .frame(maxWidth: .infinity)
                                .padding(20)
                        }
                        .defaultScrollAnchor(model.hasAttached ? .top : .center)
                    } else {
                        connectionOverlay.padding(20)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if focusMode {
                        Button("Show controls", systemImage: "arrow.down.right.and.arrow.up.left") {
                            focusMode = false
                        }
                        .labelStyle(.iconOnly)
                        .frame(minWidth: 44, minHeight: 44)
                        .herdieGlass()
                        .padding(12)
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if !focusMode {
                        VStack(spacing: 0) {
                            if !showingWriting && (model.showingComposer || environment.preferences.composerMode) {
                                ComposerBar(model: model, autoSend: environment.preferences.autoSend)
                            }

                        }
                    }
                }
                .overlay(alignment: .bottom) {
                    ZStack {
                        if showsDock {
                            navigationDock.padding(.bottom, 8)
                                .transition(.opacity)
                        }
                    }
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: showsDock)
                }
                .background(terminalBackground)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close terminal", systemImage: "chevron.left", action: closeTerminal)
                    }
                    ToolbarItem(placement: .principal) { terminalHeader }
                    ToolbarItem(placement: .topBarTrailing) { sessionMenu }
                }
                .toolbar(focusMode ? .hidden : .visible, for: .navigationBar)
                .toolbarBackground(.hidden, for: .navigationBar)
                .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(environment.preferences.appearance.colorScheme)
        .tint(HerdieTheme.accent)
        .background(terminalBackground.ignoresSafeArea())
        .sensoryFeedback(.selection, trigger: submissionFeedback)
        .sensoryFeedback(.selection, trigger: model.controlArmed) { _, armed in armed }
        .task(id: model.isRecovering) {
            loadingVisible = false
            guard model.isRecovering else { return }
            do {
                try await Task.sleep(for: .milliseconds(250))
                loadingVisible = true
            } catch { }
        }
        .task {
            while !Task.isCancelled {
                await model.poll()
                let cadence: Duration = model.state == .attached ? .milliseconds(16) : .milliseconds(100)
                try? await Task.sleep(for: cadence)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                model.suspend()
            case .active:
                Task { await model.resume() }
            default:
                break
            }
        }
        .sheet(isPresented: $showingWorkspaces) {
            WorkspaceSheet(model: model)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingAgents) {
            AgentSheet(model: model)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingReader) {
            NavigationStack {
                TerminalOutputReader(text: readingSnapshot.isEmpty ? "No terminal output yet." : readingSnapshot, allowedURLs: readingURLs)
                .navigationTitle("Read output")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Back to live") { showingReader = false }
                    }
                }
            }
        }
        .sheet(isPresented: $showingWriting) {
            TerminalWritingSheet(model: model) {
                submissionFeedback += 1
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingTerminalAppearance) {
            NavigationStack {
                TerminalAppearanceSettingsView(preferences: environment.preferences)
                    .toolbar { ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showingTerminalAppearance = false }
                    } }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingDetails) {
            NavigationStack {
                List {
                    Section("Connection") {
                        LabeledContent("Host", value: model.connection.host)
                        LabeledContent("User", value: model.connection.username)
                        LabeledContent("Status", value: stateLabel)
                    }
                    if let details = model.errorMessage {
                        Section("Technical details") {
                            Text(details).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                        }
                    }
                }
                .navigationTitle("Connection details")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingDetails = false }
                } }
            }
            .presentationDragIndicator(.visible)
        }
        .alert("Verify SSH Host", isPresented: Binding(
            get: { model.pendingHostKey != nil },
            set: { if !$0 { model.rejectPendingHostKey() } }
        )) {
            Button("Cancel", role: .cancel) { model.rejectPendingHostKey() }
            Button(model.pendingHostKey?.isMismatch == true ? "Trust New Key" : "Trust & Connect") {
                do {
                    try model.approvePendingHostKey()
                } catch {
                    model.errorMessage = error.localizedDescription
                }
            }
        } message: {
            if let hostKey = model.pendingHostKey {
                if let expected = hostKey.expected {
                    Text("The host key changed. Expected \(expected), received \(hostKey.presented). Only continue if you verified the change.")
                } else {
                    Text("First connection to this host. Verify its SHA-256 fingerprint:\n\(hostKey.presented)")
                }
            }
        }
        .alert("Session Error", isPresented: Binding(
            get: {
                model.pendingHostKey == nil
                    && model.errorMessage != nil
                    && !showsConnectionRecovery
                    && !model.isRecovering
                    && !showingWriting
            },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .onDisappear {
            finishSessionIfNeeded()
        }
    }

    private var terminalHeader: some View {
        Button {
            dismissKeyboard()
            showingWorkspaces = true
        } label: {
            VStack(spacing: 2) {
                HStack(spacing: 5) {
                    Text(model.connection.name).font(.headline).lineLimit(1)
                    Image(systemName: "chevron.down").font(.caption2.bold())
                }
                Text(stateLabel).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
        }
        .foregroundStyle(.primary)
        .accessibilityLabel("Herdr workspaces")
        .accessibilityValue("\(model.connection.name), \(stateLabel)")
    }

    private var sessionMenu: some View {
        Menu("Session actions", systemImage: "ellipsis") {
            Button("Read terminal output", systemImage: "doc.text.magnifyingglass") {
                dismissKeyboard()
                readingSnapshot = model.frame.text
                readingURLs = Set(TerminalLinkDetector.links(in: model.frame).map(\.url))
                showingReader = true
            }
            Button("Toggle full-screen pane", systemImage: "arrow.up.left.and.arrow.down.right") {
                model.togglePaneFocus()
            }
            .disabled(model.state != .attached)
            Button("Hide controls", systemImage: "viewfinder") {
                dismissKeyboard()
                focusMode = true
            }
            Divider()
            Button("Terminal appearance", systemImage: "textformat.size") {
                dismissKeyboard()
                showingTerminalAppearance = true
            }
            Button("Connection details", systemImage: "info.circle") { showingDetails = true }
        }
    }

    private var navigationDock: some View {
        HStack(spacing: 8) {
            dockButton("Running agents", title: "Agents", symbol: "person.2") {
                dismissKeyboard()
                showingAgents = true
            }
            .disabled(model.state != .attached)
            dockButton("Write a message", title: "Write", symbol: "square.and.pencil") {
                dismissKeyboard()
                showingWriting = true
            }
            dockButton("Show keyboard", title: "Keyboard", symbol: "keyboard") {
                model.perform(.keyboard)
            }
            .disabled(model.state != .attached)
        }
        .padding(6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay { Capsule().strokeBorder(.primary.opacity(0.08), lineWidth: 0.5) }
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(.horizontal, 20)
        .animation(reduceMotion ? nil : .snappy(duration: 0.24), value: dockCollapsed)
    }

    private func dockButton(_ label: String, title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                if !dockCollapsed { Text(title).transition(.opacity) }
            }
            .font(.subheadline.weight(.medium))
            .frame(minWidth: 44, minHeight: 44)
            .padding(.horizontal, dockCollapsed ? 0 : 8)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(label)
    }

    @ViewBuilder
    private var connectionOverlay: some View {
        if model.pendingHostKey == nil {
            if model.isRecovering {
                if loadingVisible {
                    HStack(spacing: 12) {
                        ProgressView()
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.hasAttached ? "Reconnecting…" : "Connecting to \(model.connection.name)…")
                                .font(.subheadline.weight(.medium))
                            if model.hasAttached {
                                Text("Last output remains available.").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(18)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                    .accessibilityElement(children: .combine)
                }
            } else if showsConnectionRecovery {
                ConnectionRecoveryCard(
                    destination: model.connection.destination,
                    message: model.connectionRecoveryMessage,
                    technicalDetails: model.errorMessage,
                    mayHaveNetworkRestriction: model.mayHaveNetworkRestriction,
                    isRetrying: model.hasAttached,
                    onRetry: model.retry,
                    onClose: closeTerminal
                )
            } else if model.state == .idle {
                VStack(spacing: 12) {
                    Label("Session closed", systemImage: "terminal").font(.headline)
                    Button("Reconnect", action: model.retry).buttonStyle(.borderedProminent)
                }
                .padding(20)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            }
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private var stateLabel: String {
        if model.isRecovering { return model.hasAttached ? "Reconnecting…" : "Connecting…" }
        return switch model.state {
        case .idle: "Disconnected"
        case .connecting: "Connecting…"
        case .attached: "Herdr attached"
        case .reconnecting: "Connection interrupted"
        }
    }

    private var showsConnectionRecovery: Bool {
        guard model.pendingHostKey == nil, !model.isRecovering, model.errorMessage != nil else { return false }
        return model.state == .idle || model.state == .reconnecting
    }

    private func handleResize(columns: UInt16, rows: UInt16) {
        if hasConnected {
            model.resize(columns: columns, rows: rows)
        } else {
            hasConnected = true
            model.connectReportingErrors(columns: columns, rows: rows)
        }
    }

    private func paste() {
        if let value = UIPasteboard.general.string {
            model.paste(value)
        }
    }

    private func closeTerminal() {
        finishSessionIfNeeded()
        dismiss()
    }

    private func finishSessionIfNeeded() {
        guard !hasEnded else { return }
        hasEnded = true
        model.disconnect()
        onSessionEnded(model.frame)
    }
}

/// Observe high-frequency frame changes here, not in the surrounding screen.
private struct LiveTerminalCanvas: View {
    let model: TerminalViewModel
    let preferences: AppPreferences
    let bottomClearance: CGFloat
    let onScrollDirection: (Int) -> Void
    let onResize: (UInt16, UInt16) -> Void
    let onPaste: () -> Void
    let onFocusChanged: (Bool) -> Void

    var body: some View {
        TerminalCanvas(
            terminalFrame: model.frame,
            theme: preferences.terminalTheme,
            fontSize: CGFloat(preferences.terminalFontSize),
            bottomClearance: bottomClearance,
            toolbarActions: preferences.toolbarActions.filter { $0 != .keyboard && $0 != .composer },
            controlArmed: model.controlArmed,
            onToolbarAction: model.perform,
            focusGeneration: model.keyboardGeneration,
            onInput: model.sendInput,
            onResize: onResize,
            onScroll: { rows in
                onScrollDirection(rows)
                model.scroll(by: rows)
            },
            onSwitchPane: { forward in
                guard model.state == .attached else { return }
                model.switchPane(forward: forward)
                UISelectionFeedbackGenerator().selectionChanged()
            },
            onPaste: onPaste,
            onFocusChanged: onFocusChanged
        )
    }
}

private struct ConnectionRecoveryCard: View {
    let destination: String
    let message: String
    let technicalDetails: String?
    let mayHaveNetworkRestriction: Bool
    let isRetrying: Bool
    let onRetry: () -> Void
    let onClose: () -> Void
    @State private var showingSetup = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 34))
                .foregroundStyle(.orange)
            VStack(spacing: 6) {
                Text(isRetrying ? "Connection interrupted" : "Couldn’t connect")
                    .font(.headline)
                Text(destination)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(HerdieTheme.secondary)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(HerdieTheme.secondary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }
            Button(action: onRetry) {
                Text("Try Again").frame(maxWidth: .infinity)
            }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("retry-connection")
            HStack {
                Button("Connection help") { showingSetup = true }
                    .accessibilityIdentifier("connection-help")
                Spacer()
                Button("Close", action: onClose)
            }
            .font(.subheadline)
            .frame(minHeight: 44)
        }
        .padding(22)
        .frame(maxWidth: 420)
        .herdieCard(cornerRadius: 24)
        .sheet(isPresented: $showingSetup) {
            ConnectionSetupHelp(
                mayHaveNetworkRestriction: mayHaveNetworkRestriction,
                technicalDetails: technicalDetails
            )
        }
    }
}

private struct ConnectionSetupHelp: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let mayHaveNetworkRestriction: Bool
    let technicalDetails: String?

    var body: some View {
        NavigationStack {
            List {
                if mayHaveNetworkRestriction {
                    Section("Check this device first") {
                        Text("The system denied this connection. A device permission or VPN restriction may be responsible.")
                    }
                }
                Section("1. Allow local connections") {
                    Text("In Settings → Privacy & Security → Local Network, enable Herdie if it appears. Each iPhone and iPad has its own permission.")
                    Button("Open Herdie Settings", systemImage: "gear") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    Text("If there is no Local Network switch, return to Herdie, try connecting while the app is open, and allow the prompt if shown.")
                        .font(.footnote)
                        .foregroundStyle(HerdieTheme.secondary)
                }
                Section("2. Check Tailscale, if you use it") {
                    Text("Open Tailscale on this device. Confirm it is connected to the same network as your host and that the host is online.")
                    Text("Try pinging the host from Tailscale. If that fails, check the VPN connection and your tailnet access rules before retrying Herdie.")
                }
                Section("3. Check the SSH host") {
                    Text("On your Mac, open System Settings → General → Sharing and enable Remote Login for your user.")
                    Text("Check the saved host address, SSH port, and username. For Tailscale, use the host’s Tailscale IP or full MagicDNS name.")
                    Text("If the host is reachable but SSH still fails, check the host firewall and the saved password or private key.")
                }
                if let technicalDetails {
                    Section {
                        DisclosureGroup("Technical details") {
                            Text(technicalDetails)
                                .font(.system(.footnote, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .navigationTitle("Connection help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct TerminalWritingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: TerminalViewModel
    let onSubmitted: () -> Void
    @FocusState private var editorFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Label(model.connection.name, systemImage: "terminal")
                    .font(.subheadline.weight(.medium))
                Text("Send to the active terminal pane. Return adds a new line here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if model.composerDraft.isEmpty, let lastDraft = model.lastSubmittedDraft {
                    Button("Restore last message", systemImage: "arrow.uturn.backward") {
                        model.composerDraft = lastDraft
                    }
                    .font(.footnote)
                }
                if model.state != .attached {
                    Label("Reconnect to send. Your draft is kept here.", systemImage: "wifi.exclamationmark")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                TextEditor(text: $model.composerDraft)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .focused($editorFocused)
                    .accessibilityLabel("Message draft")
                    .overlay(alignment: .topLeading) {
                        if model.composerDraft.isEmpty {
                            Text("Write a message…")
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                if let error = model.errorMessage, model.state == .attached {
                    Text(error).font(.footnote).foregroundStyle(.red).textSelection(.enabled)
                }
            }
            .padding(20)
            .navigationTitle("Write a message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Keep draft") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send", systemImage: "arrow.up") {
                        if model.sendComposer() {
                            onSubmitted()
                            dismiss()
                        }
                    }
                    .labelStyle(.titleAndIcon)
                    .disabled(model.composerDraft.isEmpty || model.state != .attached)
                }
            }
        }
        .task { editorFocused = true }
    }
}

private struct ComposerBar: View {
    @Bindable var model: TerminalViewModel
    let autoSend: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Compose a message", text: $model.composerDraft, axis: .vertical)
                .lineLimit(1 ... 5)
                .textFieldStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(HerdieTheme.raisedSurface, in: RoundedRectangle(cornerRadius: 18))
                .accessibilityLabel("Composer")
                .onChange(of: model.composerDraft) {
                    model.autoSendComposerIfNeeded(isEnabled: autoSend)
                }
            Button {
                model.sendComposer()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.headline)
                    .foregroundStyle(HerdieTheme.onAccent)
                    .frame(width: 42, height: 42)
                    .background(HerdieTheme.accent, in: Circle())
            }
            .disabled(model.composerDraft.isEmpty || model.state != .attached)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .background(.ultraThinMaterial)
    }
}

private struct TerminalOutputReader: UIViewRepresentable {
    let text: String
    let allowedURLs: Set<URL>

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        view.adjustsFontForContentSizeCategory = true
        view.linkTextAttributes = [.foregroundColor: UIColor(HerdieTheme.accent), .underlineStyle: NSUnderlineStyle.single.rawValue]
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        guard view.text != text else { return }
        let content = NSMutableAttributedString(string: text, attributes: [
            .font: UIFont.monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular),
            .foregroundColor: UIColor.label
        ])
        for match in TerminalLinkDetector.matches(in: text) where allowedURLs.contains(match.url) {
            content.addAttribute(.link, value: match.url, range: match.range)
        }
        view.attributedText = content
    }
}
