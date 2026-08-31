import Foundation
import Security

protocol CredentialVault: AnyObject {
    func save(_ credential: StoredCredential, for connectionID: UUID) throws
    func load(for connectionID: UUID) throws -> StoredCredential?
    func delete(for connectionID: UUID) throws
}

enum CredentialVaultError: LocalizedError {
    case keychain(OSStatus)
    case corruptCredential

    var errorDescription: String? {
        switch self {
        case let .keychain(status): "Keychain operation failed (\(status))."
        case .corruptCredential: "The saved credential could not be read."
        }
    }
}

final class KeychainCredentialVault: CredentialVault {
    private let service: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(service: String = "com.lucasscariot.herdie.credentials") {
        self.service = service
    }

    func save(_ credential: StoredCredential, for connectionID: UUID) throws {
        let data = try encoder.encode(credential)
        let query = baseQuery(connectionID)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw CredentialVaultError.keychain(updateStatus)
        }

        var add = query
        add.merge(attributes) { _, replacement in replacement }
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw CredentialVaultError.keychain(status) }
    }

    func load(for connectionID: UUID) throws -> StoredCredential? {
        var query = baseQuery(connectionID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw CredentialVaultError.keychain(status) }
        guard let data = result as? Data,
              let credential = try? decoder.decode(StoredCredential.self, from: data)
        else {
            throw CredentialVaultError.corruptCredential
        }
        return credential
    }

    func delete(for connectionID: UUID) throws {
        let status = SecItemDelete(baseQuery(connectionID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialVaultError.keychain(status)
        }
    }

    private func baseQuery(_ connectionID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: connectionID.uuidString
        ]
    }
}

final class InMemoryCredentialVault: CredentialVault {
    private var credentials: [UUID: StoredCredential] = [:]

    func save(_ credential: StoredCredential, for connectionID: UUID) throws {
        credentials[connectionID] = credential
    }

    func load(for connectionID: UUID) throws -> StoredCredential? {
        credentials[connectionID]
    }

    func delete(for connectionID: UUID) throws {
        credentials[connectionID] = nil
    }
}
