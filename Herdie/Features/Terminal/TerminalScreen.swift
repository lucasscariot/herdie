import SwiftUI
import UIKit

struct TerminalScreen: View {
    @Environment(\.dismiss) private var dismiss
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
    @State private var showingWriting = false
    @State private var keyboardVisible = false

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
        ZStack {
            HerdieTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                terminalHeader
                ZStack {
                    LiveTerminalCanvas(
                        model: model,
                        onResize: handleResize,
                        onPaste: paste
                    )
                    .accessibilityIdentifier("terminal-canvas")
                    if showsConnectionRecovery {
                        ConnectionRecoveryCard(
                            destination: model.connection.destination,
                            message: model.connectionRecoveryMessage,
                            isRetrying: model.state == .reconnecting,
                            onRetry: model.retry,
                            onClose: closeTerminal
                        )
                        .padding(24)
                    }
                }
                if model.showingComposer || environment.preferences.composerMode {
                    ComposerBar(
                        model: model,
                        autoSend: environment.preferences.autoSend
                    )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if keyboardVisible {
                    TerminalToolbar(
                        model: model,
                        actions: environment.preferences.toolbarActions,
                        onPaste: paste
                    )
                }
                navigationDock
            }
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
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardVisible = false
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
                ScrollView {
                    Text(readingSnapshot.isEmpty ? "No terminal output yet." : readingSnapshot)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
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
            NavigationStack {
                TextEditor(text: $model.composerDraft)
                    .padding()
                    .accessibilityLabel("Message draft")
                    .navigationTitle("Write a message")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Keep draft") { showingWriting = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Send") {
                                model.sendComposer()
                                showingWriting = false
                            }
                            .disabled(model.composerDraft.isEmpty || model.state != .attached)
                        }
                    }
            }
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
        HStack(spacing: 12) {
            Button {
                finishSessionIfNeeded()
                dismiss()
            } label: {
                Image(systemName: "minus")
                    .font(.headline)
                    .foregroundStyle(HerdieTheme.onAccent)
                    .frame(width: 34, height: 34)
                    .background(statusColor, in: Circle())
            }
            .accessibilityLabel("Close terminal")

            VStack(alignment: .leading, spacing: 2) {
                Text(model.connection.name)
                    .font(.system(.subheadline, design: .monospaced))
                    .lineLimit(1)
                Text(stateLabel)
                    .font(.caption2)
                    .foregroundStyle(HerdieTheme.secondary)
            }
            Spacer()
            Button {
                showingWorkspaces = true
            } label: {
                Label("Workspaces", systemImage: "rectangle.3.group")
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .frame(width: 38, height: 34)
            }
            .accessibilityLabel("Herdr workspaces")
            Text("SSH")
                .font(.caption.bold())
                .foregroundStyle(HerdieTheme.blue)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(HerdieTheme.blue.opacity(0.12), in: Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var navigationDock: some View {
        HStack(spacing: 0) {
            dockButton("Running agents", symbol: "person.2") {
                dismissKeyboard()
                showingAgents = true
            }
            .disabled(model.state != .attached)
            dockButton("Toggle full-screen pane", symbol: "arrow.up.left.and.arrow.down.right") {
                dismissKeyboard()
                model.togglePaneFocus()
            }
            .disabled(model.state != .attached)
            dockButton("Read terminal output", symbol: "doc.text.magnifyingglass") {
                dismissKeyboard()
                readingSnapshot = model.frame.text
                showingReader = true
            }
            dockButton("Write a message", symbol: "square.and.pencil") {
                dismissKeyboard()
                showingWriting = true
            }
            dockButton("Show keyboard", symbol: "keyboard") {
                model.perform(.keyboard)
            }
        }
        .frame(height: 44)
        .padding(.horizontal, 8)
        .background(.ultraThinMaterial)
        .accessibilityIdentifier("terminal-navigation-dock")
    }

    private func dockButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .medium))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tint(HerdieTheme.accent)
        .accessibilityLabel(title)
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private var stateLabel: String {
        switch model.state {
        case .idle: "Disconnected"
        case .connecting: "Connecting…"
        case .attached: "Herdr attached"
        case .reconnecting: "Ready to reattach"
        }
    }

    private var statusColor: Color {
        switch model.state {
        case .idle: HerdieTheme.secondary
        case .connecting: .yellow
        case .attached: HerdieTheme.accent
        case .reconnecting: .orange
        }
    }

    private var showsConnectionRecovery: Bool {
        guard model.pendingHostKey == nil, model.errorMessage != nil else { return false }
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
    let onResize: (UInt16, UInt16) -> Void
    let onPaste: () -> Void

    var body: some View {
        TerminalCanvas(
            terminalFrame: model.frame,
            focusGeneration: model.keyboardGeneration,
            onInput: model.sendInput,
            onResize: onResize,
            onScroll: model.scroll,
            onSwitchPane: model.switchPane,
            onPaste: onPaste
        )
    }
}

private struct ConnectionRecoveryCard: View {
    let destination: String
    let message: String
    let isRetrying: Bool
    let onRetry: () -> Void
    let onClose: () -> Void

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
            Button("Try Again", action: onRetry)
                .font(.headline)
                .foregroundStyle(HerdieTheme.onAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(HerdieTheme.accent, in: Capsule())
                .accessibilityIdentifier("retry-connection")
            Button("Close", action: onClose)
                .font(.subheadline)
        }
        .padding(22)
        .frame(maxWidth: 420)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(.white.opacity(0.08))
        }
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
            .disabled(model.composerDraft.isEmpty)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .background(.ultraThinMaterial)
    }
}

private struct TerminalToolbar: View {
    let model: TerminalViewModel
    let actions: [ToolbarAction]
    let onPaste: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(actions) { action in
                    Button {
                        if action == .paste {
                            onPaste()
                        } else {
                            model.perform(action)
                        }
                    } label: {
                        Group {
                            if let symbol = action.systemImage {
                                Image(systemName: symbol)
                            } else {
                                Text(action.title)
                                    .font(.system(.subheadline, design: .monospaced).weight(.medium))
                            }
                        }
                        .frame(minWidth: 42, minHeight: 42)
                        .padding(.horizontal, action.systemImage == nil ? 5 : 0)
                        .foregroundStyle(action == .control && model.controlArmed ? HerdieTheme.onAccent : Color.primary)
                        .background(
                            action == .control && model.controlArmed
                                ? HerdieTheme.accent
                                : HerdieTheme.raisedSurface,
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(HerdieTheme.border, lineWidth: 0.5)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(action.title)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
        }
        .background(.ultraThinMaterial)
    }
}
