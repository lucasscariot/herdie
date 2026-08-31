import XCTest
@testable import Herdie

@MainActor
final class TerminalViewModelTests: XCTestCase {
    func testConnectLoadsCredentialAcrossTheSessionInterface() throws {
        let connection = SavedConnection.fixture(authentication: .password)
        let repository = InMemoryConnectionRepository(connections: [connection])
        let vault = InMemoryCredentialVault()
        try vault.save(.password("secret"), for: connection.id)
        let session = InMemorySessionClient()
        let model = TerminalViewModel(
            connection: connection,
            repository: repository,
            credentialVault: vault,
            session: session
        )

        try model.connect(columns: 100, rows: 30)

        XCTAssertEqual(session.connectRequests.count, 1)
        XCTAssertEqual(session.connectRequests[0].authentication, .password("secret"))
        XCTAssertEqual(session.connectRequests[0].columns, 100)
    }

    func testUnknownHostRequiresApprovalAndReconnectsWithPinnedKey() async throws {
        let connection = SavedConnection.fixture()
        let repository = InMemoryConnectionRepository(connections: [connection])
        let vault = InMemoryCredentialVault()
        let session = InMemorySessionClient()
        let model = TerminalViewModel(
            connection: connection,
            repository: repository,
            credentialVault: vault,
            session: session
        )
        try model.connect(columns: 80, rows: 24)
        session.events.append(.hostKeyUnknown(presented: "SHA256:new"))

        await model.poll()
        XCTAssertEqual(model.pendingHostKey?.presented, "SHA256:new")

        try model.approvePendingHostKey()

        XCTAssertEqual(session.connectRequests.count, 2)
        XCTAssertEqual(session.connectRequests.last?.expectedHostKey, "SHA256:new")
        XCTAssertEqual(try repository.load().first?.hostKeyFingerprint, "SHA256:new")
    }

    func testToolbarAndControlLatchSendTerminalBytes() async throws {
        let session = InMemorySessionClient()
        let model = TerminalViewModel(
            connection: .fixture(),
            repository: InMemoryConnectionRepository(),
            credentialVault: InMemoryCredentialVault(),
            session: session
        )
        session.events.append(.stateChanged(.attached))
        await model.poll()

        model.perform(.escape)
        model.perform(.tab)
        model.perform(.herdrPrefix)
        model.perform(.control)
        model.sendText("c")

        XCTAssertEqual(session.sent, [Data([0x1B]), Data([0x09]), Data([0x00]), Data([0x03])])
        XCTAssertFalse(model.controlArmed)
    }

    func testSuspensionOnlyClosesTheLocalSession() {
        let session = InMemorySessionClient()
        let model = TerminalViewModel(
            connection: .fixture(),
            repository: InMemoryConnectionRepository(),
            credentialVault: InMemoryCredentialVault(),
            session: session
        )

        model.suspend()

        XCTAssertEqual(session.disconnectReasons, [.appSuspended])
    }

    func testResumePollsTheSuspensionTransitionAndReconnects() async throws {
        let session = InMemorySessionClient()
        let scheduler = ManualReconnectScheduler()
        let model = TerminalViewModel(
            connection: .fixture(),
            repository: InMemoryConnectionRepository(),
            credentialVault: InMemoryCredentialVault(),
            session: session,
            reconnectScheduler: scheduler
        )
        try model.connect(columns: 80, rows: 24)
        model.suspend()
        session.events.append(.stateChanged(.reconnecting))

        await model.resume()
        XCTAssertEqual(session.connectRequests.count, 1)

        scheduler.runNext()

        XCTAssertEqual(session.connectRequests.count, 2)
    }

    func testActiveNetworkInterruptionReconnectsOnce() async throws {
        let session = InMemorySessionClient()
        let scheduler = ManualReconnectScheduler()
        let model = TerminalViewModel(
            connection: .fixture(),
            repository: InMemoryConnectionRepository(),
            credentialVault: InMemoryCredentialVault(),
            session: session,
            reconnectScheduler: scheduler
        )
        try model.connect(columns: 80, rows: 24)
        session.events.append(.stateChanged(.reconnecting))

        await model.poll()
        XCTAssertEqual(session.connectRequests.count, 1)

        scheduler.runNext()

        XCTAssertEqual(session.connectRequests.count, 2)
    }

    func testReconnectPolicyStopsAfterFourDelayedAttempts() async throws {
        let session = InMemorySessionClient()
        let scheduler = ManualReconnectScheduler()
        let model = TerminalViewModel(
            connection: .fixture(),
            repository: InMemoryConnectionRepository(),
            credentialVault: InMemoryCredentialVault(),
            session: session,
            reconnectScheduler: scheduler
        )
        try model.connect(columns: 80, rows: 24)

        for _ in 0..<4 {
            session.events.append(.stateChanged(.reconnecting))
            await model.poll()
            XCTAssertTrue(scheduler.hasPendingAction)
            scheduler.runNext()
        }
        session.events.append(.stateChanged(.reconnecting))
        await model.poll()

        XCTAssertFalse(scheduler.hasPendingAction)
        XCTAssertEqual(session.connectRequests.count, 5)
        XCTAssertNotNil(model.errorMessage)
    }

    func testShortLivedAttachmentsDoNotResetTheReconnectBudget() async throws {
        let session = InMemorySessionClient()
        let scheduler = ManualReconnectScheduler()
        let model = TerminalViewModel(
            connection: .fixture(),
            repository: InMemoryConnectionRepository(),
            credentialVault: InMemoryCredentialVault(),
            session: session,
            reconnectScheduler: scheduler
        )
        try model.connect(columns: 80, rows: 24)

        for _ in 0..<4 {
            session.events.append(.stateChanged(.reconnecting))
            await model.poll()
            scheduler.runNext()
            session.events.append(.stateChanged(.attached))
            await model.poll()
        }
        session.events.append(.stateChanged(.reconnecting))
        await model.poll()

        XCTAssertFalse(scheduler.hasPendingAction)
        XCTAssertEqual(session.connectRequests.count, 5)
    }

    func testRemoteExitDoesNotScheduleAReconnect() async throws {
        let session = InMemorySessionClient()
        let scheduler = ManualReconnectScheduler()
        let model = TerminalViewModel(
            connection: .fixture(),
            repository: InMemoryConnectionRepository(),
            credentialVault: InMemoryCredentialVault(),
            session: session,
            reconnectScheduler: scheduler
        )
        try model.connect(columns: 80, rows: 24)
        session.events.append(contentsOf: [
            .error("Herdr exited with status 127"),
            .stateChanged(.idle)
        ])

        await model.poll()

        XCTAssertFalse(scheduler.hasPendingAction)
        XCTAssertEqual(session.connectRequests.count, 1)
    }

    func testManualRetryClearsTheErrorAndStartsANewConnection() async throws {
        let session = InMemorySessionClient()
        let model = TerminalViewModel(
            connection: .fixture(),
            repository: InMemoryConnectionRepository(),
            credentialVault: InMemoryCredentialVault(),
            session: session
        )
        try model.connect(columns: 80, rows: 24)
        session.events.append(contentsOf: [
            .error("SSH connection failed: host not found"),
            .stateChanged(.idle)
        ])
        await model.poll()

        model.retry()

        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(session.connectRequests.count, 2)
    }

    func testDisconnectedTerminalOperationsPreserveTheConnectionFailure() async throws {
        let session = InMemorySessionClient()
        let model = TerminalViewModel(
            connection: .fixture(),
            repository: InMemoryConnectionRepository(),
            credentialVault: InMemoryCredentialVault(),
            session: session
        )
        try model.connect(columns: 80, rows: 24)
        session.events.append(contentsOf: [
            .error("SSH connection failed: host not found"),
            .stateChanged(.idle)
        ])
        await model.poll()

        model.resize(columns: 100, rows: 30)
        model.sendText("pwd\n")
        model.scroll(by: 4)

        XCTAssertEqual(model.errorMessage, "SSH connection failed: host not found")
        XCTAssertTrue(session.sizes.isEmpty)
        XCTAssertTrue(session.sent.isEmpty)
        XCTAssertTrue(session.scrollDeltas.isEmpty)
    }

    func testAttachedConversationScrollForwardsSignedRowsToTheRemoteTerminal() async {
        let session = InMemorySessionClient()
        let model = TerminalViewModel(
            connection: .fixture(),
            repository: InMemoryConnectionRepository(),
            credentialVault: InMemoryCredentialVault(),
            session: session
        )
        session.events.append(.stateChanged(.attached))
        await model.poll()

        model.scroll(by: 3)
        model.scroll(by: -2)

        XCTAssertEqual(session.scrollDeltas, [3, -2])
    }

    func testResizeDuringConnectionIsAppliedAfterAttachment() async throws {
        let session = InMemorySessionClient()
        let model = TerminalViewModel(
            connection: .fixture(),
            repository: InMemoryConnectionRepository(),
            credentialVault: InMemoryCredentialVault(),
            session: session
        )
        try model.connect(columns: 80, rows: 24)
        session.events.append(.stateChanged(.connecting))
        await model.poll()

        model.resize(columns: 100, rows: 30)
        XCTAssertTrue(session.sizes.isEmpty)

        session.events.append(.stateChanged(.attached))
        await model.poll()

        XCTAssertEqual(session.sizes.count, 1)
        XCTAssertEqual(session.sizes.first?.0, 100)
        XCTAssertEqual(session.sizes.first?.1, 30)
    }

    func testControlLatchIsConsumedByANonTextInputSequence() async {
        let session = InMemorySessionClient()
        let model = TerminalViewModel(
            connection: .fixture(),
            repository: InMemoryConnectionRepository(),
            credentialVault: InMemoryCredentialVault(),
            session: session
        )
        session.events.append(.stateChanged(.attached))
        await model.poll()
        model.perform(.control)

        model.sendInput(Data([0x1B, 0x5B, 0x41]))

        XCTAssertEqual(session.sent, [Data([0x1B, 0x5B, 0x41])])
        XCTAssertFalse(model.controlArmed)
    }

    func testAutoSendSendsOneCompletedComposerLine() async {
        let session = InMemorySessionClient()
        let model = TerminalViewModel(
            connection: .fixture(),
            repository: InMemoryConnectionRepository(),
            credentialVault: InMemoryCredentialVault(),
            session: session
        )
        session.events.append(.stateChanged(.attached))
        await model.poll()
        model.composerDraft = "hello from dictation\n"

        model.autoSendComposerIfNeeded(isEnabled: true)

        XCTAssertEqual(session.sent, [Data("hello from dictation\n".utf8)])
        XCTAssertEqual(model.composerDraft, "")
    }

    func testWorkspaceActionsUseTheHerdrPrefixSequences() async {
        let session = InMemorySessionClient()
        let model = TerminalViewModel(
            connection: .fixture(),
            repository: InMemoryConnectionRepository(),
            credentialVault: InMemoryCredentialVault(),
            session: session
        )
        session.events.append(.stateChanged(.attached))
        await model.poll()

        model.switchWorkspacePrevious()
        model.switchWorkspaceNext()
        model.createWorkspace()

        XCTAssertEqual(session.sent, [
            Data([0x00, 0x50]),
            Data([0x00, 0x4E]),
            Data([0x00, 0x43])
        ])
    }
}

@MainActor
private final class ManualReconnectScheduler: ReconnectScheduling {
    private var action: (@MainActor () -> Void)?
    private(set) var delays: [Duration] = []

    var hasPendingAction: Bool { action != nil }

    func schedule(after delay: Duration, action: @escaping @MainActor () -> Void) {
        delays.append(delay)
        self.action = action
    }

    func cancel() {
        action = nil
    }

    func runNext() {
        let pending = action
        action = nil
        pending?()
    }
}
