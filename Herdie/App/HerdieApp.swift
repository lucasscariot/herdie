import SwiftUI

@main
@MainActor
struct HerdieApp: App {
    private let environment = AppEnvironment.live()

    var body: some Scene {
        WindowGroup {
            DashboardView(environment: environment)
                .preferredColorScheme(.dark)
                .tint(HerdieTheme.accent)
        }
    }
}
