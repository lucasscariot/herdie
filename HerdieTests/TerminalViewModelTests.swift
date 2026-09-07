import XCTest
@testable import Herdie

@MainActor
final class TerminalViewModelTests: XCTestCase {
    func testNetworkRestrictionGuidanceDoesNotMisclassifyAuthenticationErrors() {
        let model = TerminalViewModel(
            connection: .fixture(), repository: InMemoryConnectionRepository(),
            credentialVault: InMemoryCredentialVault(), session: InMemorySessionClient()
        )
        model.errorMessage = "SSH connection failed: Operation not permitted (os error 1)"
        XCTAssertTrue(model.mayHaveNetworkRestriction)
        XCTAssertTrue(model.connectionRecoveryMessage.contains("Local Network"))
        model.errorMessage = "Permission denied (publickey)"
        XCTAssertFalse(model.mayHaveNetworkRestriction)
        XCTAssertFalse(model.connectionRecoveryMessage.contains("Local Network"))
    }

    func testComposerKeepsDraftWhenSubmissionFails() async {
        let session = FailingSendSession()
        let model = TerminalViewModel(connection: .fixture(), repository: InMemoryConnectionRepository(),
                                      credentialVault: InMemoryCredentialVault(), session: session)
        await model.poll()
        model.composerDraft = "Keep my work"
        XCTAssertFalse(model.sendComposer())
        XCTAssertEqual(model.composerDraft, "Keep my work")
        XCTAssertNotNil(model.errorMessage)
        model.composerDraft = "Keep this line\n"
        model.autoSendComposerIfNeeded(isEnabled: true)
        XCTAssertEqual(model.composerDraft, "Keep this line\n")
    }

    func testConnectionProgressEndsAndAttachmentSurvivesAnInterruption() async throws {
        let session = InMemorySessionClient()
        let scheduler = ManualReconnectScheduler()
        let model = TerminalViewModel(connection: .fixture(), repository: InMemoryConnectionRepository(),
                                      credentialVault: InMemoryCredentialVault(), session: session,
                                      reconnectScheduler: scheduler)
        try model.connect(columns: 80, rows: 24)
        XCTAssertTrue(model.isConnectionPending)
        session.events = [.stateChanged(.attached)]
        await model.poll()
        XCTAssertFalse(model.isConnectionPending)
        XCTAssertTrue(model.hasAttached)
        session.events = [.stateChanged(.reconnecting)]
        await model.poll()
        XCTAssertTrue(model.isRecovering)
        XCTAssertTrue(model.hasAttached)
    }

    func testAsynchronousConnectionFailureStopsLoading() async throws {
        let session = InMemorySessionClient()
        let model = TerminalViewModel(connection: .fixture(), repository: InMemoryConnectionRepository(),
                                      credentialVault: InMemoryCredentialVault(), session: session)
        try model.connect(columns: 80, rows: 24)
        session.events = [.stateChanged(.connecting), .error("Connection rejected")]
        await model.poll()
        XCTAssertFalse(model.isRecovering)
        XCTAssertEqual(model.state, .idle)
        XCTAssertNotNil(model.errorMessage)
    }

    func testSubmittedMessageCanBeRecoveredWithoutAutomaticResending() async {
        let session = InMemorySessionClient()
        let model = TerminalViewModel(connection: .fixture(), repository: InMemoryConnectionRepository(),
                                      credentialVault: InMemoryCredentialVault(), session: session)
        session.events = [.stateChanged(.attached)]
        await model.poll()
        model.composerDraft = "Review the change"
        XCTAssertTrue(model.sendComposer())
        session.events = [.error("Queued write failed")]
        await model.poll()
        XCTAssertEqual(model.lastSubmittedDraft, "Review the change")
        XCTAssertEqual(session.sent, [Data("Review the change\n".utf8)])
        XCTAssertTrue(model.composerDraft.isEmpty)
    }

    func testCommandSubmissionDoesNotWaitForBusyCoreAndPreservesOrder() async {
        let queue = DispatchQueue(label: "HerdieTests.busy-core")
        queue.suspend()
        let commands = SessionCommandQueue(queue: queue)
        let started = ContinuousClock.now
        commands.enqueue { throw QueueTestError.first }
        commands.enqueue { throw QueueTestError.second }
        let elapsed = started.duration(to: .now)
        queue.resume()
        XCTAssertLessThan(elapsed, .milliseconds(100))
        let events = await commands.poll { [] }
        XCTAssertEqual(events, [.error("first"), .error("second")])
        let next = await commands.poll { [] }
        XCTAssertTrue(next.isEmpty, "Command errors must only be delivered once")
    }

    func testDrawingOnlyVisitsRowsIntersectingDamage() {
        XCTAssertEqual(TerminalCanvasView.drawingRows(
            in: CGRect(x: 0, y: 40, width: 400, height: 20), cellHeight: 20, rows: 100
        ), 2..<3)
        XCTAssertEqual(TerminalCanvasView.drawingRows(
            in: CGRect(x: 0, y: -10, width: 400, height: 40), cellHeight: 20, rows: 100
        ), 0..<2)
        XCTAssertEqual(TerminalCanvasView.drawingRows(
            in: CGRect(x: 0, y: 3000, width: 400, height: 20), cellHeight: 20, rows: 100
        ), 100..<100)
    }

    private enum QueueTestError: LocalizedError {
        case first, second
        var errorDescription: String? { self == .first ? "first" : "second" }
    }

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
        model.switchPane(forward: true)
        model.switchPane(forward: false)

        XCTAssertEqual(session.sent, [
            Data([0x00, 0x50]),
            Data([0x00, 0x4E]),
            Data([0x00, 0x43]),
            Data([0x00, 0x09]),
            Data([0x00, 0x1B, 0x5B, 0x5A])
        ])
    }

    func testAgentListAndFocusUseStructuredSessionControls() async {
        let session = InMemorySessionClient()
        let model = TerminalViewModel(
            connection: .fixture(),
            repository: InMemoryConnectionRepository(),
            credentialVault: InMemoryCredentialVault(),
            session: session
        )
        session.events.append(.stateChanged(.attached))
        await model.poll()

        model.refreshAgents()
        XCTAssertTrue(model.isLoadingAgents)
        XCTAssertEqual(session.agentListRequestCount, 1)

        let agent = RunningAgent(
            agent: "codex",
            status: .working,
            workspaceID: "w2",
            tabID: "w2:t1",
            paneID: "w2:p4",
            title: "herdr-ios",
            provider: "codex",
            context: "50k",
            limit: "7d 79%",
            focused: false
        )
        session.events.append(.agentsUpdated([agent]))
        await model.poll()

        XCTAssertEqual(model.agents, [agent])
        XCTAssertFalse(model.isLoadingAgents)

        model.focusAgent(agent)

        XCTAssertEqual(session.focusedAgentPaneIDs, ["w2:p4"])
        XCTAssertTrue(model.agents[0].focused)
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

@MainActor
private final class FailingSendSession: SessionClient {
    func connect(_ request: SessionConnectRequest) throws { }
    func send(_ data: Data) throws { throw CocoaError(.fileWriteUnknown) }
    func resize(columns: UInt16, rows: UInt16) throws { }
    func scroll(lines: Int32) throws { }
    func listAgents() throws { }
    func focusAgent(paneID: String) throws { }
    func poll() async -> [SessionEvent] { [.stateChanged(.attached)] }
    func disconnect(_ reason: SessionDisconnectReason) { }
}
