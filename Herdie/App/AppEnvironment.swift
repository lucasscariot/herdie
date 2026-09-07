import Foundation

@MainActor
final class AppEnvironment {
    let connectionRepository: ConnectionRepository
    let credentialVault: CredentialVault
    let preferences: AppPreferences
    let dashboard: DashboardViewModel
    private let sessionFactory: () -> SessionClient

    init(
        connectionRepository: ConnectionRepository,
        credentialVault: CredentialVault,
        preferences: AppPreferences,
        sessionFactory: @escaping () -> SessionClient
    ) {
        self.connectionRepository = connectionRepository
        self.credentialVault = credentialVault
        self.preferences = preferences
        self.sessionFactory = sessionFactory
        dashboard = DashboardViewModel(
            repository: connectionRepository,
            credentialVault: credentialVault
        )
    }

    static func live(processInfo: ProcessInfo = .processInfo) -> AppEnvironment {
        let isUITesting = processInfo.arguments.contains("--ui-testing")
        if isUITesting {
            let simulatesConnectionFailure = processInfo.arguments.contains("--simulate-connection-failure")
            let connections: [SavedConnection] = processInfo.arguments.contains("--seed-demo")
                ? Self.demoConnections
                : []
            let repository = InMemoryConnectionRepository(connections: connections)
            let suiteName = "HerdieUITests"
            let defaults = UserDefaults(suiteName: suiteName) ?? .standard
            if processInfo.arguments.contains("--reset-storage") {
                defaults.removePersistentDomain(forName: suiteName)
            }
            return AppEnvironment(
                connectionRepository: repository,
                credentialVault: InMemoryCredentialVault(),
                preferences: AppPreferences(defaults: defaults),
                sessionFactory: {
                    if simulatesConnectionFailure {
                        return SimulatedConnectionFailureSessionClient()
                    }
                    return DemoSessionClient(slowConnection: processInfo.arguments.contains("--slow-connection"))
                }
            )
        }
        return AppEnvironment(
            connectionRepository: UserDefaultsConnectionRepository(),
            credentialVault: KeychainCredentialVault(),
            preferences: AppPreferences(),
            sessionFactory: { RustSessionClient() }
        )
    }

    func makeSessionClient() -> SessionClient {
        sessionFactory()
    }

    private static let demoConnections: [SavedConnection] = [
        SavedConnection(
            id: UUID(uuidString: "10CFA087-9A80-43C5-9106-701ECE79EA8D")!,
            name: "Mac Studio",
            host: "studio.tailnet.ts.net",
            port: 22,
            username: "lucas",
            authentication: .none,
            hostKeyFingerprint: nil
        ),
        SavedConnection(
            id: UUID(uuidString: "E9286155-50B5-4E1B-9216-C3A30D170BAC")!,
            name: "Home Server",
            host: "192.168.1.42",
            port: 22,
            username: "lucas",
            authentication: .none,
            hostKeyFingerprint: nil
        )
    ]
}

private final class SimulatedConnectionFailureSessionClient: SessionClient {
    private var events: [SessionEvent] = []

    func connect(_ request: SessionConnectRequest) throws {
        events.append(contentsOf: [
            .stateChanged(.connecting),
            .error("SSH connection failed: failed to lookup address information: nodename nor servname provided, or not known"),
            .stateChanged(.idle)
        ])
    }

    func send(_ data: Data) throws {}
    func resize(columns: UInt16, rows: UInt16) throws {}
    func scroll(lines: Int32) throws {}
    func listAgents() throws {}
    func focusAgent(paneID: String) throws {}

    func poll() async -> [SessionEvent] {
        defer { events.removeAll() }
        return events
    }

    func disconnect(_ reason: SessionDisconnectReason) {}
}

/// Deterministic UI preview. Never opens a network connection.
private final class DemoSessionClient: SessionClient {
    private let slowConnection: Bool
    private var readyAt: Date?
    private var events: [SessionEvent] = []
    private var columns: UInt16 = 80
    private var rows: UInt16 = 24
    private var output = """
    ~/projects/herdie

    › Review the terminal experience

    ◉ Working on your request

      ✓ Reviewed the session lifecycle
      ✓ Checked keyboard interactions
      ✓ Preserved your working changes

      The terminal is ready.
      What would you like to work on next?

    ›
    """

    init(slowConnection: Bool) { self.slowConnection = slowConnection }

    func connect(_ request: SessionConnectRequest) throws {
        columns = request.columns
        rows = request.rows
        events = [.stateChanged(.connecting)]
        readyAt = .now.addingTimeInterval(slowConnection ? 3 : 0.4)
    }
    func send(_ data: Data) throws {
        if let text = String(data: data, encoding: .utf8), !text.contains("\0") {
            output += text
            events.append(.terminalFrame(snapshot()))
        }
    }
    func resize(columns: UInt16, rows: UInt16) throws {
        self.columns = columns
        self.rows = rows
        events.append(.terminalFrame(snapshot()))
    }
    func scroll(lines: Int32) throws { }
    func listAgents() throws {
        events.append(.agentsUpdated([
            RunningAgent(agent: "codex", status: .working, workspaceID: "Main", tabID: "Herdie", paneID: "p1",
                         title: "Terminal polish", provider: "Codex", context: "Herdie", limit: nil, focused: true),
            RunningAgent(agent: "claude", status: .blocked, workspaceID: "Main", tabID: "Review", paneID: "p2",
                         title: "Review changes", provider: "Claude", context: "Waiting for input", limit: nil, focused: false)
        ]))
    }
    func focusAgent(paneID: String) throws { }
    func poll() async -> [SessionEvent] {
        if let readyAt, Date.now >= readyAt {
            self.readyAt = nil
            events += [.stateChanged(.attached), .terminalFrame(snapshot())]
        }
        defer { events.removeAll() }
        return events
    }
    func disconnect(_ reason: SessionDisconnectReason) {
        readyAt = nil
        events = [.stateChanged(reason == .appSuspended ? .reconnecting : .idle)]
    }
    private func snapshot() -> TerminalUpdate {
        let lines = output.components(separatedBy: "\n").map(Array.init)
        let cells = (0..<Int(rows)).flatMap { row in
            (0..<Int(columns)).map { column in
                let contents = row < lines.count && column < lines[row].count ? String(lines[row][column]) : " "
                return TerminalCell(row: UInt16(row), column: UInt16(column), contents: contents,
                                    foreground: row == 4 ? .indexed(index: 5) : .default, background: .default,
                                    bold: row == 4, italic: false, underline: false, inverse: false)
            }
        }
        return TerminalUpdate(columns: columns, rows: rows, scrollbackOffset: 0,
                              cursor: TerminalCursor(row: UInt16(min(lines.count - 1, Int(rows) - 1)), column: 2, visible: true),
                              cells: cells, text: output, full: true)
    }
}
