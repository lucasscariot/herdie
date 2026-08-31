import Foundation

enum AppSessionState: Equatable, Sendable {
    case idle
    case connecting
    case attached
    case reconnecting
}

enum SessionDisconnectReason: Equatable, Sendable {
    case userRequested
    case appSuspended
    case networkLost
}

enum SessionAuthentication: Equatable, Sendable {
    case none
    case password(String)
    case privateKey(key: String, passphrase: String?)
}

struct SessionConnectRequest: Equatable, Sendable {
    var connection: SavedConnection
    var authentication: SessionAuthentication
    var expectedHostKey: String?
    var columns: UInt16
    var rows: UInt16
}

enum SessionEvent: Equatable, Sendable {
    case stateChanged(AppSessionState)
    case terminalFrame(TerminalUpdate)
    case hostKeyUnknown(presented: String)
    case hostKeyMismatch(expected: String, presented: String)
    case error(String)
}

@MainActor
protocol SessionClient: AnyObject {
    func connect(_ request: SessionConnectRequest) throws
    func send(_ data: Data) throws
    func resize(columns: UInt16, rows: UInt16) throws
    func scroll(lines: Int32) throws
    func poll() async -> [SessionEvent]
    func disconnect(_ reason: SessionDisconnectReason)
}

final class InMemorySessionClient: SessionClient {
    var connectRequests: [SessionConnectRequest] = []
    var sent: [Data] = []
    var sizes: [(UInt16, UInt16)] = []
    var scrollDeltas: [Int32] = []
    var events: [SessionEvent] = []
    var disconnectReasons: [SessionDisconnectReason] = []

    func connect(_ request: SessionConnectRequest) throws {
        connectRequests.append(request)
    }

    func send(_ data: Data) throws {
        sent.append(data)
    }

    func resize(columns: UInt16, rows: UInt16) throws {
        sizes.append((columns, rows))
    }

    func scroll(lines: Int32) throws {
        scrollDeltas.append(lines)
    }

    func poll() async -> [SessionEvent] {
        defer { events.removeAll() }
        return events
    }

    func disconnect(_ reason: SessionDisconnectReason) {
        disconnectReasons.append(reason)
    }
}
