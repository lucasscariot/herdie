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

enum RunningAgentStatus: Equatable, Sendable {
    case unknown
    case idle
    case working
    case blocked
    case done
}

struct RunningAgent: Identifiable, Equatable, Sendable {
    var id: String { paneID }
    var agent: String
    var status: RunningAgentStatus
    var workspaceID: String
    var tabID: String
    var paneID: String
    var title: String
    var provider: String?
    var context: String?
    var limit: String?
    var focused: Bool
}

enum SessionEvent: Equatable, Sendable {
    case stateChanged(AppSessionState)
    case terminalFrame(TerminalUpdate)
    case hostKeyUnknown(presented: String)
    case hostKeyMismatch(expected: String, presented: String)
    case agentsUpdated([RunningAgent])
    case error(String)
}

@MainActor
protocol SessionClient: AnyObject {
    func connect(_ request: SessionConnectRequest) throws
    func send(_ data: Data) throws
    func resize(columns: UInt16, rows: UInt16) throws
    func scroll(lines: Int32) throws
    func listAgents() throws
    func focusAgent(paneID: String) throws
    func poll() async -> [SessionEvent]
    func disconnect(_ reason: SessionDisconnectReason)
}

final class InMemorySessionClient: SessionClient {
    var connectRequests: [SessionConnectRequest] = []
    var sent: [Data] = []
    var sizes: [(UInt16, UInt16)] = []
    var scrollDeltas: [Int32] = []
    var agentListRequestCount = 0
    var focusedAgentPaneIDs: [String] = []
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

    func listAgents() throws {
        agentListRequestCount += 1
    }

    func focusAgent(paneID: String) throws {
        focusedAgentPaneIDs.append(paneID)
    }

    func poll() async -> [SessionEvent] {
        defer { events.removeAll() }
        return events
    }

    func disconnect(_ reason: SessionDisconnectReason) {
        disconnectReasons.append(reason)
    }
}
