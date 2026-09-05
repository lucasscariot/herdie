import Foundation

final class RustSessionClient: SessionClient {
    private let core = HerdieCore()
    private let commands = SessionCommandQueue()

    func connect(_ request: SessionConnectRequest) throws {
        debugLog("connect requested for \(request.connection.destination)")
        let profile = ConnectionProfile(
            id: request.connection.id.uuidString,
            name: request.connection.name,
            host: request.connection.host,
            port: request.connection.port,
            username: request.connection.username
        )
        let authentication: Authentication = switch request.authentication {
        case .none:
            .none
        case let .password(secret):
            .password(secret: secret)
        case let .privateKey(key, passphrase):
            .privateKey(key: key, passphrase: passphrase)
        }
        let core = core
        commands.enqueue {
            try core.connect(
                profile: profile,
                authentication: authentication,
                expectedHostKey: request.expectedHostKey,
                columns: request.columns,
                rows: request.rows
            )
        }
        debugLog("connect accepted by core")
    }

    func send(_ data: Data) throws {
        let core = core
        commands.enqueue {
            try core.send(input: data)
        }
    }

    func resize(columns: UInt16, rows: UInt16) throws {
        let core = core
        commands.enqueue {
            try core.resize(columns: columns, rows: rows)
        }
    }

    func scroll(lines: Int32) throws {
        let core = core
        commands.enqueue {
            try core.scroll(lines: lines)
        }
    }

    func listAgents() throws {
        let core = core
        commands.enqueue {
            try core.listAgents()
        }
    }

    func focusAgent(paneID: String) throws {
        let core = core
        commands.enqueue {
            try core.focusAgent(paneId: paneID)
        }
    }

    func poll() async -> [SessionEvent] {
        let core = core
        return await commands.poll {
            core.pollEvents().compactMap(Self.map)
        }
    }

    func disconnect(_ reason: SessionDisconnectReason) {
        let mapped: DisconnectReason = switch reason {
        case .userRequested: .userRequested
        case .appSuspended: .appSuspended
        case .networkLost: .networkLost
        }
        let core = core
        commands.enqueue {
            core.disconnect(reason: mapped)
        }
    }

    nonisolated private static func map(_ event: CoreEvent) -> SessionEvent? {
        switch event.kind {
        case .stateChanged:
            guard let state = event.state else { return nil }
            debugLog("state changed to \(state)")
            return .stateChanged(Self.map(state))
        case .terminalFrame:
            guard let update = event.terminalUpdate else { return nil }
            return .terminalFrame(update)
        case .hostKeyUnknown:
            guard let presented = event.presentedHostKey else { return nil }
            debugLog("received unknown host key")
            return .hostKeyUnknown(presented: presented)
        case .hostKeyMismatch:
            guard let expected = event.expectedHostKey,
                  let presented = event.presentedHostKey
            else { return nil }
            debugLog("received mismatched host key")
            return .hostKeyMismatch(expected: expected, presented: presented)
        case .agentsUpdated:
            guard let agents = event.agents else { return nil }
            return .agentsUpdated(agents.map(Self.map))
        case .error:
            let message = event.message ?? "The SSH session failed."
            debugLog("error: \(message)")
            return .error(message)
        }
    }

    nonisolated private static func map(_ agent: AgentSnapshot) -> RunningAgent {
        let status: RunningAgentStatus = switch agent.status {
        case .unknown: .unknown
        case .idle: .idle
        case .working: .working
        case .blocked: .blocked
        case .done: .done
        }
        return RunningAgent(
            agent: agent.agent,
            status: status,
            workspaceID: agent.workspaceId,
            tabID: agent.tabId,
            paneID: agent.paneId,
            title: agent.title,
            provider: agent.provider,
            context: agent.context,
            limit: agent.limit,
            focused: agent.focused
        )
    }

    nonisolated private static func map(_ state: SessionState) -> AppSessionState {
        switch state {
        case .idle: .idle
        case .connecting: .connecting
        case .attached: .attached
        case .reconnecting: .reconnecting
        }
    }

    nonisolated private static func debugLog(_ message: String) {
#if DEBUG
        print("[Herdie SSH] \(message)")
#endif
    }

    private func debugLog(_ message: String) {
        Self.debugLog(message)
    }
}

/// All state below is confined to queue. Submission never waits on the UI thread.
/// Commands and polls execute FIFO; command failures are delivered by the next poll.
final class SessionCommandQueue: @unchecked Sendable {
    private let queue: DispatchQueue
    private var failures: [SessionEvent] = []

    init(queue: DispatchQueue = DispatchQueue(label: "com.lucasscariot.herdie.ssh-core", qos: .userInitiated)) {
        self.queue = queue
    }

    func enqueue(_ command: @escaping @Sendable () throws -> Void) {
        queue.async { [self] in
            do { try command() }
            catch { failures.append(.error(error.localizedDescription)) }
        }
    }

    func poll(_ read: @escaping @Sendable () -> [SessionEvent]) async -> [SessionEvent] {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                let events = read() + failures
                failures.removeAll(keepingCapacity: true)
                continuation.resume(returning: events)
            }
        }
    }
}
