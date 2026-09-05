import SwiftUI

@main
@MainActor
struct HerdieApp: App {
    private let environment = AppEnvironment.live()

    var body: some Scene {
        WindowGroup {
            HerdieRootView(environment: environment)
        }
    }
}

private struct HerdieRootView: View {
    let environment: AppEnvironment

    var body: some View {
        DashboardView(environment: environment)
            .preferredColorScheme(environment.preferences.appearance.colorScheme)
            .tint(HerdieTheme.accent)
    }
}
