import Foundation

enum AuthenticationMethod: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case password
    case privateKey

    var id: Self { self }

    var title: String {
        switch self {
        case .none: "None"
        case .password: "Password"
        case .privateKey: "Key File"
        }
    }
}

struct SavedConnection: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var name: String
    var host: String
    var port: UInt16
    var username: String
    var authentication: AuthenticationMethod
    var hostKeyFingerprint: String?

    var destination: String {
        "\(username)@\(host):\(port)"
    }
}

enum StoredCredential: Codable, Equatable, Sendable {
    case password(String)
    case privateKey(key: String, passphrase: String?)
}

enum ConnectionValidationError: LocalizedError, Equatable {
    case missingName
    case missingHost
    case invalidPort
    case missingUsername
    case missingPassword
    case missingPrivateKey

    var errorDescription: String? {
        switch self {
        case .missingName: "Enter a name for this connection."
        case .missingHost: "Enter a hostname or IP address."
        case .invalidPort: "Enter a port from 1 to 65535."
        case .missingUsername: "Enter the SSH username."
        case .missingPassword: "Enter a password or choose None authentication."
        case .missingPrivateKey: "Import or paste an OpenSSH private key."
        }
    }
}

struct ConnectionBuildResult: Equatable {
    var connection: SavedConnection
    var credential: StoredCredential?
}

struct ConnectionDraft: Equatable {
    var id = UUID()
    var name = ""
    var host = ""
    var port = "22"
    var username = ""
    var authentication: AuthenticationMethod = .none
    var password = ""
    var privateKey = ""
    var passphrase = ""
    var hostKeyFingerprint: String?
    var isEditing = false
    private var originalAuthentication: AuthenticationMethod?
    private var originalHost: String?
    private var originalPort: UInt16?

    var canKeepExistingCredential: Bool {
        isEditing && authentication == originalAuthentication && authentication != .none
    }

    init() {}

    init(connection: SavedConnection) {
        id = connection.id
        name = connection.name
        host = connection.host
        port = String(connection.port)
        username = connection.username
        authentication = connection.authentication
        originalAuthentication = connection.authentication
        originalHost = connection.host
        originalPort = connection.port
        hostKeyFingerprint = connection.hostKeyFingerprint
        isEditing = true
    }

    func build() throws -> ConnectionBuildResult {
        try build(
            requiringCredential: !isEditing || authentication != originalAuthentication
        )
    }

    func build(requiringCredential: Bool) throws -> ConnectionBuildResult {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw ConnectionValidationError.missingName }
        guard !cleanHost.isEmpty else { throw ConnectionValidationError.missingHost }
        guard let numericPort = UInt16(port), numericPort > 0 else {
            throw ConnectionValidationError.invalidPort
        }
        guard !cleanUsername.isEmpty else { throw ConnectionValidationError.missingUsername }

        let credential: StoredCredential?
        switch authentication {
        case .none:
            credential = nil
        case .password:
            if password.isEmpty {
                guard !requiringCredential else { throw ConnectionValidationError.missingPassword }
                credential = nil
            } else {
                credential = .password(password)
            }
        case .privateKey:
            if privateKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                guard !requiringCredential else { throw ConnectionValidationError.missingPrivateKey }
                credential = nil
            } else {
                credential = .privateKey(
                    key: privateKey,
                    passphrase: passphrase.isEmpty ? nil : passphrase
                )
            }
        }

        return ConnectionBuildResult(
            connection: SavedConnection(
                id: id,
                name: cleanName,
                host: cleanHost,
                port: numericPort,
                username: cleanUsername,
                authentication: authentication,
                hostKeyFingerprint: endpointIsUnchanged(host: cleanHost, port: numericPort)
                    ? hostKeyFingerprint
                    : nil
            ),
            credential: credential
        )
    }

    private func endpointIsUnchanged(host: String, port: UInt16) -> Bool {
        guard isEditing, let originalHost, let originalPort else { return false }
        return host.caseInsensitiveCompare(originalHost) == .orderedSame && port == originalPort
    }
}
