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

struct TerminalScrollSettings: Codable, Equatable {
    static let triggerRange = 0.1...1.0
    static let speedRange = 0.5...3.0
    static let deadZoneRange = 2.0...20.0

    /// Fraction of a line the finger travels before the next line scrolls.
    var trigger = 0.5
    /// Lines scrolled per line of finger travel.
    var speed = 1.0
    /// Points a drag moves before it commits to scrolling or switching panes.
    var deadZone = 10.0

    var clamped: Self {
        Self(
            trigger: min(max(trigger, Self.triggerRange.lowerBound), Self.triggerRange.upperBound),
            speed: min(max(speed, Self.speedRange.lowerBound), Self.speedRange.upperBound),
            deadZone: min(max(deadZone, Self.deadZoneRange.lowerBound), Self.deadZoneRange.upperBound)
        )
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
    var terminalTheme: TerminalTheme { didSet { save() } }
    var terminalFontSize: Double { didSet { save() } }
    var scrolling: TerminalScrollSettings { didSet { save() } }
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
            terminalTheme = stored.terminalTheme ?? .herdie
            terminalFontSize = min(max(stored.terminalFontSize ?? 14, 11), 20)
            scrolling = (stored.scrolling ?? TerminalScrollSettings()).clamped
            autoSend = stored.autoSend
            toolbarActions = stored.toolbarActions.isEmpty ? ToolbarAction.defaults : stored.toolbarActions
        } else {
            composerMode = false
            appearance = .system
            terminalTheme = .herdie
            terminalFontSize = 14
            scrolling = TerminalScrollSettings()
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
            appearance: appearance,
            terminalTheme: terminalTheme,
            terminalFontSize: terminalFontSize,
            scrolling: scrolling
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
        var terminalTheme: TerminalTheme?
        var terminalFontSize: Double?
        var scrolling: TerminalScrollSettings?
    }
}
