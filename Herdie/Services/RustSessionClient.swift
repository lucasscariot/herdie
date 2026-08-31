import Foundation

final class RustSessionClient: SessionClient {
    private let core = HerdieCore()

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
        try core.connect(
            profile: profile,
            authentication: authentication,
            expectedHostKey: request.expectedHostKey,
            columns: request.columns,
            rows: request.rows
        )
        debugLog("connect accepted by core")
    }

    func send(_ data: Data) throws {
        try core.send(input: data)
    }

    func resize(columns: UInt16, rows: UInt16) throws {
        try core.resize(columns: columns, rows: rows)
    }

    func scroll(rows: UInt32) throws {
        try core.scroll(rows: rows)
    }

    func poll() -> [SessionEvent] {
        core.pollEvents().compactMap { event in
            switch event.kind {
            case .stateChanged:
                guard let state = event.state else { return nil }
                debugLog("state changed to \(state)")
                return .stateChanged(Self.map(state))
            case .terminalFrame:
                guard let snapshot = event.terminalSnapshotJson else { return nil }
                return .terminalFrame(snapshot)
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
    }

    func disconnect(_ reason: SessionDisconnectReason) {
        let mapped: DisconnectReason = switch reason {
        case .userRequested: .userRequested
        case .appSuspended: .appSuspended
        case .networkLost: .networkLost
        }
        core.disconnect(reason: mapped)
    }

    private static func map(_ state: SessionState) -> AppSessionState {
        switch state {
        case .idle: .idle
        case .connecting: .connecting
        case .attached: .attached
        case .reconnecting: .reconnecting
        }
    }

    private func debugLog(_ message: String) {
#if DEBUG
        print("[Herdie SSH] \(message)")
#endif
    }
}
