import Foundation
import Observation

struct PendingHostKey: Equatable, Sendable {
    var expected: String?
    var presented: String
    var isMismatch: Bool { expected != nil }
}

enum TerminalViewModelError: LocalizedError {
    case missingCredential

    var errorDescription: String? {
        "This connection has no credential in Keychain. Edit it to add one."
    }
}

@MainActor
protocol ReconnectScheduling: AnyObject {
    func schedule(after delay: Duration, action: @escaping @MainActor () -> Void)
    func cancel()
}

@MainActor
final class TaskReconnectScheduler: ReconnectScheduling {
    private var task: Task<Void, Never>?

    func schedule(after delay: Duration, action: @escaping @MainActor () -> Void) {
        cancel()
        task = Task {
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            action()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

@MainActor
@Observable
final class TerminalViewModel {
    private(set) var connection: SavedConnection
    private(set) var state: AppSessionState = .idle
    private(set) var frame = TerminalFrame.empty
    private(set) var controlArmed = false
    private(set) var agents: [RunningAgent] = []
    private(set) var isLoadingAgents = false
    var pendingHostKey: PendingHostKey?
    var errorMessage: String?
    var composerDraft = ""
    var showingComposer = false
    var keyboardGeneration = 0

    var connectionRecoveryMessage: String {
        guard let errorMessage else { return "The SSH session is unavailable." }
        let normalized = errorMessage.lowercased()
        let nameResolutionMarkers = [
            "failed to lookup address information",
            "nodename nor servname",
            "name or service not known",
            "could not resolve hostname",
            "host not found",
            "no such host"
        ]
        guard nameResolutionMarkers.contains(where: normalized.contains) else {
            return errorMessage
        }
        return """
        The host name could not be resolved. Use an IP address, a working .local name, or the full Tailscale MagicDNS name.

        \(errorMessage)
        """
    }

    private let repository: ConnectionRepository
    private let credentialVault: CredentialVault
    private let session: SessionClient
    private let reconnectScheduler: ReconnectScheduling
    private let reconnectDelays: [Duration]
    private let reconnectStabilityDelay: Duration
    private var lastColumns: UInt16 = 80
    private var lastRows: UInt16 = 24
    private var lastSentColumns: UInt16 = 80
    private var lastSentRows: UInt16 = 24
    private var wasSuspended = false
    private var reconnectAttempt = 0
    private var reconnectScheduled = false
    private var stabilityResetScheduled = false

    init(
        connection: SavedConnection,
        repository: ConnectionRepository,
        credentialVault: CredentialVault,
        session: SessionClient,
        reconnectScheduler: ReconnectScheduling = TaskReconnectScheduler(),
        reconnectDelays: [Duration] = [
            .milliseconds(250),
            .seconds(1),
            .seconds(2),
            .seconds(4)
        ],
        reconnectStabilityDelay: Duration = .seconds(5)
    ) {
        self.connection = connection
        self.repository = repository
        self.credentialVault = credentialVault
        self.session = session
        self.reconnectScheduler = reconnectScheduler
        self.reconnectDelays = reconnectDelays
        self.reconnectStabilityDelay = reconnectStabilityDelay
    }

    func connect(columns: UInt16, rows: UInt16) throws {
        lastColumns = max(columns, 1)
        lastRows = max(rows, 1)
        let authentication = try loadAuthentication()
        try session.connect(SessionConnectRequest(
            connection: connection,
            authentication: authentication,
            expectedHostKey: connection.hostKeyFingerprint,
            columns: lastColumns,
            rows: lastRows
        ))
        lastSentColumns = lastColumns
        lastSentRows = lastRows
    }

    func connectReportingErrors(columns: UInt16, rows: UInt16) {
        do {
            try connect(columns: columns, rows: rows)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resize(columns: UInt16, rows: UInt16) {
        let safeColumns = max(columns, 1)
        let safeRows = max(rows, 1)
        lastColumns = safeColumns
        lastRows = safeRows
        guard state == .attached else { return }
        applyPendingResize()
    }

    func poll() async {
        for event in await session.poll() {
            consume(event)
        }
    }

    func approvePendingHostKey() throws {
        guard let pendingHostKey else { return }
        connection.hostKeyFingerprint = pendingHostKey.presented
        try repository.save(connection)
        self.pendingHostKey = nil
        try connect(columns: lastColumns, rows: lastRows)
    }

    func rejectPendingHostKey() {
        resetReconnectPolicy()
        pendingHostKey = nil
        session.disconnect(.userRequested)
        state = .idle
    }

    func sendText(_ text: String) {
        guard state == .attached, !text.isEmpty else { return }
        let data: Data
        if controlArmed, let byte = controlByte(for: text) {
            data = Data([byte])
            controlArmed = false
        } else {
            data = Data(text.utf8)
            controlArmed = false
        }
        send(data)
    }

    func sendInput(_ data: Data) {
        guard state == .attached else { return }
        if controlArmed, let text = String(data: data, encoding: .utf8), text.unicodeScalars.count == 1 {
            sendText(text)
        } else {
            controlArmed = false
            send(data)
        }
    }

    func sendComposer() {
        guard state == .attached, !composerDraft.isEmpty else { return }
        sendText(composerDraft + "\n")
        composerDraft = ""
    }

    func autoSendComposerIfNeeded(isEnabled: Bool) {
        guard state == .attached, isEnabled, composerDraft.hasSuffix("\n") else { return }
        let completedText = composerDraft
        composerDraft = ""
        sendText(completedText)
    }

    func paste(_ value: String) {
        sendText(value)
    }

    func perform(_ action: ToolbarAction) {
        switch action {
        case .control:
            if state == .attached {
                controlArmed.toggle()
            }
        case .composer:
            showingComposer.toggle()
        case .keyboard:
            keyboardGeneration += 1
        case .paste:
            break
        default:
            if let bytes = action.byteSequence { send(bytes) }
        }
    }

    func switchWorkspacePrevious() {
        send(Data([0x00, 0x50]))
    }

    func switchWorkspaceNext() {
        send(Data([0x00, 0x4E]))
    }

    func createWorkspace() {
        send(Data([0x00, 0x43]))
    }

    func switchPane(forward: Bool) {
        // Herdr cycles the current tab's panes; a single pane stays focused.
        send(Data(forward ? [0x00, 0x09] : [0x00, 0x1B, 0x5B, 0x5A]))
    }

    func scroll(by delta: Int) {
        guard state == .attached, delta != 0 else { return }
        do {
            try session.scroll(lines: Int32(clamping: delta))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshAgents() {
        guard state == .attached, !isLoadingAgents else { return }
        isLoadingAgents = true
        do {
            try session.listAgents()
        } catch {
            isLoadingAgents = false
            errorMessage = error.localizedDescription
        }
    }

    func focusAgent(_ agent: RunningAgent) {
        guard state == .attached else { return }
        do {
            try session.focusAgent(paneID: agent.paneID)
            agents = agents.map { candidate in
                var updated = candidate
                updated.focused = candidate.id == agent.id
                return updated
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func suspend() {
        guard !wasSuspended else { return }
        resetReconnectPolicy()
        wasSuspended = true
        session.disconnect(.appSuspended)
        state = .reconnecting
    }

    func resume() async {
        guard wasSuspended else { return }
        await poll()
        wasSuspended = false
        guard state == .reconnecting else { return }
        scheduleReconnectIfNeeded()
    }

    func disconnect() {
        resetReconnectPolicy()
        session.disconnect(.userRequested)
        state = .idle
    }

    func retry() {
        guard state == .idle || state == .reconnecting else { return }
        resetReconnectPolicy()
        errorMessage = nil
        connectReportingErrors(columns: lastColumns, rows: lastRows)
    }

    private func consume(_ event: SessionEvent) {
        switch event {
        case let .stateChanged(newState):
            state = newState
            switch newState {
            case .attached:
                errorMessage = nil
                applyPendingResize()
                scheduleReconnectBudgetReset()
            case .idle:
                resetReconnectPolicy()
            case .reconnecting:
                cancelStabilityReset()
                scheduleReconnectIfNeeded()
            case .connecting:
                break
            }
        case let .terminalFrame(update):
            do {
                try frame.apply(update)
            } catch {
                errorMessage = "Terminal output could not be rendered."
            }
        case let .hostKeyUnknown(presented):
            pendingHostKey = PendingHostKey(expected: nil, presented: presented)
        case let .hostKeyMismatch(expected, presented):
            pendingHostKey = PendingHostKey(
                expected: expected,
                presented: presented
            )
        case let .agentsUpdated(agents):
            self.agents = agents
            isLoadingAgents = false
        case let .error(message):
            isLoadingAgents = false
            errorMessage = message
        }
    }

    private func loadAuthentication() throws -> SessionAuthentication {
        switch connection.authentication {
        case .none:
            return .none
        case .password:
            guard case let .password(secret)? = try credentialVault.load(for: connection.id) else {
                throw TerminalViewModelError.missingCredential
            }
            return .password(secret)
        case .privateKey:
            guard case let .privateKey(key, passphrase)? = try credentialVault.load(for: connection.id) else {
                throw TerminalViewModelError.missingCredential
            }
            return .privateKey(key: key, passphrase: passphrase)
        }
    }

    private func send(_ data: Data) {
        guard state == .attached else { return }
        do {
            try session.send(data)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyPendingResize() {
        guard lastColumns != lastSentColumns || lastRows != lastSentRows else { return }
        do {
            try session.resize(columns: lastColumns, rows: lastRows)
            lastSentColumns = lastColumns
            lastSentRows = lastRows
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func scheduleReconnectIfNeeded() {
        guard state == .reconnecting, !wasSuspended, !reconnectScheduled else { return }
        guard reconnectAttempt < reconnectDelays.count else {
            if errorMessage == nil {
                errorMessage = "Herdie could not reconnect after \(reconnectDelays.count) attempts."
            }
            return
        }
        let delay = reconnectDelays[reconnectAttempt]
        reconnectAttempt += 1
        reconnectScheduled = true
        reconnectScheduler.schedule(after: delay) { [weak self] in
            guard let self else { return }
            self.reconnectScheduled = false
            guard self.state == .reconnecting, !self.wasSuspended else { return }
            do {
                try self.connect(columns: self.lastColumns, rows: self.lastRows)
            } catch {
                self.errorMessage = error.localizedDescription
                self.scheduleReconnectIfNeeded()
            }
        }
    }

    private func scheduleReconnectBudgetReset() {
        reconnectScheduler.cancel()
        reconnectScheduled = false
        stabilityResetScheduled = true
        reconnectScheduler.schedule(after: reconnectStabilityDelay) { [weak self] in
            guard let self else { return }
            self.stabilityResetScheduled = false
            guard self.state == .attached else { return }
            self.reconnectAttempt = 0
        }
    }

    private func cancelStabilityReset() {
        guard stabilityResetScheduled else { return }
        reconnectScheduler.cancel()
        stabilityResetScheduled = false
    }

    private func resetReconnectPolicy() {
        reconnectScheduler.cancel()
        reconnectAttempt = 0
        reconnectScheduled = false
        stabilityResetScheduled = false
    }

    private func controlByte(for text: String) -> UInt8? {
        guard let scalar = text.unicodeScalars.first, scalar.isASCII else { return nil }
        let value = UInt8(scalar.value)
        switch value {
        case 0x40 ... 0x5F: return value & 0x1F
        case 0x61 ... 0x7A: return (value - 0x20) & 0x1F
        default: return nil
        }
    }
}
