import Foundation
import Observation

@MainActor
@Observable
final class SupportConfiguration {
    private(set) var isEnabled = false

    func refresh() async {
        isEnabled = false
        do {
            let url = URL(string: "https://lucasscariot.github.io/herdie/config.json")!
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
            request.timeoutInterval = 10
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  data.count < 4096 else { return }
            let config = try JSONDecoder().decode(Configuration.self, from: data)
            isEnabled = config.supportLinkEnabled
        } catch {
            // No cached permission: failed refreshes keep the support link hidden.
            isEnabled = false
        }
    }

    private struct Configuration: Decodable {
        let supportLinkEnabled: Bool
    }
}
