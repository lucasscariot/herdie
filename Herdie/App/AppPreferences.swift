import Foundation
import Observation

@MainActor
@Observable
final class AppPreferences {
    var composerMode: Bool { didSet { save() } }
    var autoSend: Bool { didSet { save() } }
    var toolbarActions: [ToolbarAction] { didSet { save() } }

    private let defaults: UserDefaults
    private let key = "herdie.preferences.v1"
    private var isLoading = true

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let stored = try? JSONDecoder().decode(Stored.self, from: data)
        {
            composerMode = stored.composerMode
            autoSend = stored.autoSend
            toolbarActions = stored.toolbarActions.isEmpty ? ToolbarAction.defaults : stored.toolbarActions
        } else {
            composerMode = false
            autoSend = false
            toolbarActions = ToolbarAction.defaults
        }
        isLoading = false
    }

    func resetToolbar() {
        toolbarActions = ToolbarAction.defaults
    }

    private func save() {
        guard !isLoading else { return }
        let stored = Stored(
            composerMode: composerMode,
            autoSend: autoSend,
            toolbarActions: toolbarActions
        )
        if let data = try? JSONEncoder().encode(stored) {
            defaults.set(data, forKey: key)
        }
    }

    private struct Stored: Codable {
        var composerMode: Bool
        var autoSend: Bool
        var toolbarActions: [ToolbarAction]
    }
}
