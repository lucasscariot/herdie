import Foundation
import Observation

enum DashboardSaveError: LocalizedError {
    case credentialRollbackFailed(metadataError: Error, rollbackError: Error)

    var errorDescription: String? {
        switch self {
        case let .credentialRollbackFailed(metadataError, rollbackError):
            "Connection metadata could not be saved and the previous Keychain state "
                + "could not be restored. Metadata: \(metadataError.localizedDescription) "
                + "Rollback: \(rollbackError.localizedDescription)"
        }
    }
}

@MainActor
@Observable
final class DashboardViewModel {
    private(set) var connections: [SavedConnection] = []
    var errorMessage: String?

    private let repository: ConnectionRepository
    private let credentialVault: CredentialVault

    init(repository: ConnectionRepository, credentialVault: CredentialVault) {
        self.repository = repository
        self.credentialVault = credentialVault
        reload()
    }

    func reload() {
        do {
            connections = try repository.load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func save(_ draft: ConnectionDraft) throws -> SavedConnection {
        let result = try draft.build()
        let changesCredential = result.credential != nil || result.connection.authentication == .none
        let previousCredential: StoredCredential?
        if changesCredential {
            previousCredential = try credentialVault.load(for: result.connection.id)
        } else {
            previousCredential = nil
        }
        if let credential = result.credential {
            try credentialVault.save(credential, for: result.connection.id)
        } else if result.connection.authentication == .none {
            try credentialVault.delete(for: result.connection.id)
        }
        do {
            try repository.save(result.connection)
        } catch {
            guard changesCredential else { throw error }
            do {
                try restoreCredential(previousCredential, for: result.connection.id)
            } catch let rollbackError {
                throw DashboardSaveError.credentialRollbackFailed(
                    metadataError: error,
                    rollbackError: rollbackError
                )
            }
            throw error
        }
        reload()
        return result.connection
    }

    func delete(_ connection: SavedConnection) throws {
        let previousCredential = try credentialVault.load(for: connection.id)
        try credentialVault.delete(for: connection.id)
        do {
            try repository.delete(id: connection.id)
        } catch {
            do {
                try restoreCredential(previousCredential, for: connection.id)
            } catch let rollbackError {
                throw DashboardSaveError.credentialRollbackFailed(
                    metadataError: error,
                    rollbackError: rollbackError
                )
            }
            throw error
        }
        reload()
    }

    func move(from offsets: IndexSet, to destination: Int) {
        var reordered = connections
        reordered.move(fromOffsets: offsets, toOffset: destination)
        do {
            try repository.replaceAll(reordered)
            connections = reordered
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restoreCredential(_ credential: StoredCredential?, for connectionID: UUID) throws {
        if let credential {
            try credentialVault.save(credential, for: connectionID)
        } else {
            try credentialVault.delete(for: connectionID)
        }
    }
}
