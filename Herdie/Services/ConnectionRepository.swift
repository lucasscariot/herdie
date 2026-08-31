import Foundation

protocol ConnectionRepository: AnyObject {
    func load() throws -> [SavedConnection]
    func save(_ connection: SavedConnection) throws
    func delete(id: UUID) throws
    func replaceAll(_ connections: [SavedConnection]) throws
}

enum ConnectionRepositoryError: LocalizedError {
    case corruptStorage

    var errorDescription: String? {
        "Saved connections could not be read."
    }
}

final class UserDefaultsConnectionRepository: ConnectionRepository {
    private let defaults: UserDefaults
    private let key: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard, key: String = "herdie.connections.v1") {
        self.defaults = defaults
        self.key = key
    }

    func load() throws -> [SavedConnection] {
        guard let data = defaults.data(forKey: key) else { return [] }
        do {
            return try decoder.decode([SavedConnection].self, from: data)
        } catch {
            throw ConnectionRepositoryError.corruptStorage
        }
    }

    func save(_ connection: SavedConnection) throws {
        var connections = try load()
        if let index = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[index] = connection
        } else {
            connections.append(connection)
        }
        try replaceAll(connections)
    }

    func delete(id: UUID) throws {
        try replaceAll(try load().filter { $0.id != id })
    }

    func replaceAll(_ connections: [SavedConnection]) throws {
        defaults.set(try encoder.encode(connections), forKey: key)
    }
}

final class InMemoryConnectionRepository: ConnectionRepository {
    private var stored: [SavedConnection]

    init(connections: [SavedConnection] = []) {
        stored = connections
    }

    func load() throws -> [SavedConnection] { stored }

    func save(_ connection: SavedConnection) throws {
        if let index = stored.firstIndex(where: { $0.id == connection.id }) {
            stored[index] = connection
        } else {
            stored.append(connection)
        }
    }

    func delete(id: UUID) throws {
        stored.removeAll { $0.id == id }
    }

    func replaceAll(_ connections: [SavedConnection]) throws {
        stored = connections
    }
}
