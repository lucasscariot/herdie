import Foundation

final class RustSessionClient: SessionClient {
    private let core = HerdieCore()
    private let coreQueue = DispatchQueue(label: "com.lucasscariot.herdie.ssh-core", qos: .userInitiated)

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
        try coreQueue.sync {
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
        try coreQueue.sync {
            try core.send(input: data)
        }
    }

    func resize(columns: UInt16, rows: UInt16) throws {
        let core = core
        try coreQueue.sync {
            try core.resize(columns: columns, rows: rows)
        }
    }

    func scroll(lines: Int32) throws {
        let core = core
        try coreQueue.sync {
            try core.scroll(lines: lines)
        }
    }

    func poll() async -> [SessionEvent] {
        let core = core
        let coreQueue = coreQueue
        return await withCheckedContinuation { continuation in
            coreQueue.async {
                continuation.resume(returning: core.pollEvents().compactMap(Self.map))
            }
        }
    }

    func disconnect(_ reason: SessionDisconnectReason) {
        let mapped: DisconnectReason = switch reason {
        case .userRequested: .userRequested
        case .appSuspended: .appSuspended
        case .networkLost: .networkLost
        }
        let core = core
        coreQueue.sync {
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
        case .error:
            let message = event.message ?? "The SSH session failed."
            debugLog("error: \(message)")
            return .error(message)
        }
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
