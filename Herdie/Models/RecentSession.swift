import Foundation

struct RecentSession: Identifiable, Equatable {
    var connection: SavedConnection
    var preview: String
    var lastUsed: Date

    var id: UUID { connection.id }
}
