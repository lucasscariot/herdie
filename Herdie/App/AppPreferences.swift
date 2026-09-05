import Foundation
import Observation
import SwiftUI

enum AppAppearance: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

@MainActor
@Observable
final class AppPreferences {
    private(set) var launchCount: Int
    private(set) var makerCardDismissed: Bool
    var showsMakerCard: Bool { launchCount >= 3 && !makerCardDismissed }

    func dismissMakerCard() {
        makerCardDismissed = true
        defaults.set(true, forKey: "herdie.maker.dismissed")
    }
    var appearance: AppAppearance { didSet { save() } }
    var composerMode: Bool { didSet { save() } }
    var autoSend: Bool { didSet { save() } }
    var toolbarActions: [ToolbarAction] { didSet { save() } }

    private let defaults: UserDefaults
    private let key = "herdie.preferences.v1"
    private var isLoading = true

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let count = min(max(defaults.integer(forKey: "herdie.launchCount"), 0), 2) + 1
        launchCount = count
        makerCardDismissed = defaults.bool(forKey: "herdie.maker.dismissed")
        defaults.set(count, forKey: "herdie.launchCount")
        if let data = defaults.data(forKey: key),
           let stored = try? JSONDecoder().decode(Stored.self, from: data)
        {
            composerMode = stored.composerMode
            appearance = stored.appearance ?? .system
            autoSend = stored.autoSend
            toolbarActions = stored.toolbarActions.isEmpty ? ToolbarAction.defaults : stored.toolbarActions
        } else {
            composerMode = false
            appearance = .system
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
            toolbarActions: toolbarActions,
            appearance: appearance
        )
        if let data = try? JSONEncoder().encode(stored) {
            defaults.set(data, forKey: key)
        }
    }

    private struct Stored: Codable {
        var composerMode: Bool
        var autoSend: Bool
        var toolbarActions: [ToolbarAction]
        var appearance: AppAppearance?
    }
}
