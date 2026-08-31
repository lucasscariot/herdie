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
                    return InMemorySessionClient()
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
    func scroll(rows: UInt32) throws {}

    func poll() -> [SessionEvent] {
        defer { events.removeAll() }
        return events
    }

    func disconnect(_ reason: SessionDisconnectReason) {}
}
