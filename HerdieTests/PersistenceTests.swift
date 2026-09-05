import XCTest
import Security
@testable import Herdie

@MainActor
final class PersistenceTests: XCTestCase {
    func testMakerCardAppearsOnThirdLaunchAndDismissalPersists() throws {
        let suiteName = "HerdieTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertFalse(AppPreferences(defaults: defaults).showsMakerCard)
        XCTAssertFalse(AppPreferences(defaults: defaults).showsMakerCard)
        let thirdLaunch = AppPreferences(defaults: defaults)
        XCTAssertTrue(thirdLaunch.showsMakerCard)
        thirdLaunch.dismissMakerCard()
        XCTAssertFalse(thirdLaunch.showsMakerCard)
        XCTAssertFalse(AppPreferences(defaults: defaults).showsMakerCard)
    }

    func testMetadataRepositoryDoesNotContainCredentials() throws {
        let suiteName = "HerdieTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let repository = UserDefaultsConnectionRepository(defaults: defaults)
        let connection = SavedConnection(
            id: UUID(),
            name: "Studio",
            host: "studio.local",
            port: 22,
            username: "lucas",
            authentication: .password,
            hostKeyFingerprint: nil
        )

        try repository.save(connection)

        let encodedDefaults = String(describing: defaults.dictionaryRepresentation())
        XCTAssertFalse(encodedDefaults.contains("super-secret"))
        XCTAssertEqual(try repository.load(), [connection])
    }

    func testDeletingAConnectionAlsoDeletesItsCredential() throws {
        let connection = SavedConnection.fixture()
        let repository = InMemoryConnectionRepository(connections: [connection])
        let vault = InMemoryCredentialVault()
        try vault.save(.password("secret"), for: connection.id)
        let model = DashboardViewModel(repository: repository, credentialVault: vault)

        try model.delete(connection)

        XCTAssertTrue(model.connections.isEmpty)
        XCTAssertNil(try vault.load(for: connection.id))
    }

    func testKeychainVaultRoundTripsAndDeletesADeviceOnlyCredential() throws {
        let connectionID = UUID()
        let vault = KeychainCredentialVault(
            service: "com.lucasscariot.herdie.tests.\(UUID().uuidString)"
        )
        defer { try? vault.delete(for: connectionID) }
        let credential = StoredCredential.privateKey(
            key: "not-a-real-private-key",
            passphrase: "secret"
        )

        try vault.save(credential, for: connectionID)
        XCTAssertEqual(try vault.load(for: connectionID), credential)

        try vault.delete(for: connectionID)
        XCTAssertNil(try vault.load(for: connectionID))
    }

    func testKeychainVaultUpdatesAnExistingCredential() throws {
        let connectionID = UUID()
        let vault = KeychainCredentialVault(
            service: "com.lucasscariot.herdie.tests.\(UUID().uuidString)"
        )
        defer { try? vault.delete(for: connectionID) }

        try vault.save(.password("old"), for: connectionID)
        try vault.save(.password("new"), for: connectionID)

        XCTAssertEqual(try vault.load(for: connectionID), .password("new"))
    }

    func testFailedCredentialReplacementDoesNotPersistEditedMetadata() throws {
        let original = SavedConnection.fixture(authentication: .password)
        let repository = InMemoryConnectionRepository(connections: [original])
        let vault = FailingCredentialVault(existing: .password("old"))
        let model = DashboardViewModel(repository: repository, credentialVault: vault)
        var draft = ConnectionDraft(connection: original)
        draft.name = "Renamed Studio"
        draft.password = "new"

        XCTAssertThrowsError(try model.save(draft))
        XCTAssertEqual(try repository.load(), [original])
        XCTAssertEqual(try vault.load(for: original.id), .password("old"))
    }

    func testMetadataFailureRestoresThePreviousCredential() throws {
        let original = SavedConnection.fixture(authentication: .password)
        let repository = FailingSaveConnectionRepository(connection: original)
        let vault = InMemoryCredentialVault()
        try vault.save(.password("old"), for: original.id)
        let model = DashboardViewModel(repository: repository, credentialVault: vault)
        var draft = ConnectionDraft(connection: original)
        draft.password = "new"

        XCTAssertThrowsError(try model.save(draft))

        XCTAssertEqual(try repository.load(), [original])
        XCTAssertEqual(try vault.load(for: original.id), .password("old"))
    }

    func testMetadataDeleteFailureRestoresThePreviousCredential() throws {
        let original = SavedConnection.fixture(authentication: .password)
        let repository = FailingDeleteConnectionRepository(connection: original)
        let vault = InMemoryCredentialVault()
        try vault.save(.password("old"), for: original.id)
        let model = DashboardViewModel(repository: repository, credentialVault: vault)

        XCTAssertThrowsError(try model.delete(original))

        XCTAssertEqual(try repository.load(), [original])
        XCTAssertEqual(try vault.load(for: original.id), .password("old"))
    }
}

private enum PersistenceTestError: Error {
    case saveFailed
}

private final class FailingSaveConnectionRepository: ConnectionRepository {
    private let connection: SavedConnection

    init(connection: SavedConnection) {
        self.connection = connection
    }

    func load() throws -> [SavedConnection] { [connection] }
    func save(_ connection: SavedConnection) throws { throw PersistenceTestError.saveFailed }
    func delete(id: UUID) throws {}
    func replaceAll(_ connections: [SavedConnection]) throws {}
}

private final class FailingDeleteConnectionRepository: ConnectionRepository {
    private let connection: SavedConnection

    init(connection: SavedConnection) {
        self.connection = connection
    }

    func load() throws -> [SavedConnection] { [connection] }
    func save(_ connection: SavedConnection) throws {}
    func delete(id: UUID) throws { throw PersistenceTestError.saveFailed }
    func replaceAll(_ connections: [SavedConnection]) throws {}
}

private final class FailingCredentialVault: CredentialVault {
    private let existing: StoredCredential

    init(existing: StoredCredential) {
        self.existing = existing
    }

    func save(_ credential: StoredCredential, for connectionID: UUID) throws {
        throw CredentialVaultError.keychain(errSecAuthFailed)
    }

    func load(for connectionID: UUID) throws -> StoredCredential? {
        existing
    }

    func delete(for connectionID: UUID) throws {}
}
