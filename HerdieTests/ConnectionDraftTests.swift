import XCTest
@testable import Herdie

final class ConnectionDraftTests: XCTestCase {
    func testBuildTrimsFieldsAndCreatesPasswordCredential() throws {
        var draft = ConnectionDraft()
        draft.name = "  Studio  "
        draft.host = " studio.tailnet.ts.net "
        draft.port = "2222"
        draft.username = " lucas "
        draft.authentication = .password
        draft.password = "secret"

        let result = try draft.build()

        XCTAssertEqual(result.connection.name, "Studio")
        XCTAssertEqual(result.connection.host, "studio.tailnet.ts.net")
        XCTAssertEqual(result.connection.port, 2222)
        XCTAssertEqual(result.connection.username, "lucas")
        XCTAssertEqual(result.credential, .password("secret"))
    }

    func testBuildRejectsAnInvalidPort() {
        var draft = ConnectionDraft()
        draft.name = "Studio"
        draft.host = "studio.local"
        draft.port = "70000"
        draft.username = "lucas"

        XCTAssertThrowsError(try draft.build()) { error in
            XCTAssertEqual(error as? ConnectionValidationError, .invalidPort)
        }
    }

    func testNoneAuthenticationNeverProducesASecret() throws {
        var draft = ConnectionDraft()
        draft.name = "Tailscale"
        draft.host = "studio"
        draft.port = "22"
        draft.username = "lucas"
        draft.authentication = .none
        draft.password = "must-not-escape"

        let result = try draft.build()

        XCTAssertNil(result.credential)
        XCTAssertEqual(result.connection.authentication, .none)
    }

    func testEditingRequiresANewCredentialWhenAuthenticationChanges() {
        let connection = SavedConnection(
            id: UUID(),
            name: "Studio",
            host: "studio.local",
            port: 22,
            username: "lucas",
            authentication: .none,
            hostKeyFingerprint: nil
        )
        var draft = ConnectionDraft(connection: connection)
        draft.authentication = .password

        XCTAssertThrowsError(try draft.build()) { error in
            XCTAssertEqual(error as? ConnectionValidationError, .missingPassword)
        }
    }

    func testEditingKeepsAnExistingCredentialWhenAuthenticationIsUnchanged() throws {
        let connection = SavedConnection(
            id: UUID(),
            name: "Studio",
            host: "studio.local",
            port: 22,
            username: "lucas",
            authentication: .password,
            hostKeyFingerprint: nil
        )

        let result = try ConnectionDraft(connection: connection).build()

        XCTAssertNil(result.credential)
        XCTAssertEqual(result.connection.authentication, .password)
    }

    func testEditingTheEndpointClearsThePinnedHostKey() throws {
        var connection = SavedConnection.fixture()
        connection.hostKeyFingerprint = "SHA256:trusted"
        var draft = ConnectionDraft(connection: connection)
        draft.host = "replacement.local"

        let result = try draft.build()

        XCTAssertNil(result.connection.hostKeyFingerprint)
    }

    func testEditingNonEndpointFieldsPreservesThePinnedHostKey() throws {
        var connection = SavedConnection.fixture()
        connection.hostKeyFingerprint = "SHA256:trusted"
        var draft = ConnectionDraft(connection: connection)
        draft.name = "Renamed Studio"

        let result = try draft.build()

        XCTAssertEqual(result.connection.hostKeyFingerprint, "SHA256:trusted")
    }
}
