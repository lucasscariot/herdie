import Foundation
@testable import Herdie

extension SavedConnection {
    static func fixture(authentication: AuthenticationMethod = .none) -> SavedConnection {
        SavedConnection(
            id: UUID(uuidString: "9EBA1418-78AD-4D86-A031-DDB255D977D4")!,
            name: "Mac Studio",
            host: "studio.local",
            port: 22,
            username: "lucas",
            authentication: authentication,
            hostKeyFingerprint: nil
        )
    }
}
