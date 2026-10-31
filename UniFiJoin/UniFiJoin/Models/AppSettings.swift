import Foundation

struct AppSettings: Codable, Equatable, Sendable {
    var controllerHost: String
    var apiKey: String
    var siteID: String
    var siteName: String
    var informHost: String
    var informPort: Int
    var useHTTPS: Bool
    var trustSelfSigned: Bool
    var sshUsername: String
    var sshPassword: String
    var autoScanOnLaunch: Bool

    static let `default` = AppSettings(
        controllerHost: "",
        apiKey: "",
        siteID: "",
        siteName: "",
        informHost: "",
        informPort: 8080,
        useHTTPS: true,
        trustSelfSigned: true,
        sshUsername: "ubnt",
        sshPassword: "ubnt",
        autoScanOnLaunch: true
    )

    var isConfigured: Bool {
        !controllerHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var normalizedControllerHost: String {
        var cleaned = controllerHost.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("https://") {
            cleaned.removeFirst("https://".count)
        } else if cleaned.hasPrefix("http://") {
            cleaned.removeFirst("http://".count)
        }
        return cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// UniFi OS consoles expose Network Integration under `/proxy/network/integration`.
    /// Some installs also answer at `/integration`.
    var integrationBaseURLCandidates: [URL] {
        let host = normalizedControllerHost
        guard !host.isEmpty else { return [] }
        let scheme = useHTTPS ? "https" : "http"
        return [
            URL(string: "\(scheme)://\(host)/proxy/network/integration"),
            URL(string: "\(scheme)://\(host)/integration")
        ].compactMap { $0 }
    }

    var integrationBaseURL: URL? {
        integrationBaseURLCandidates.first
    }

    var informURL: String {
        let host: String = {
            let preferred = informHost.trimmingCharacters(in: .whitespacesAndNewlines)
            if !preferred.isEmpty { return preferred }
            var fallback = controllerHost.trimmingCharacters(in: .whitespacesAndNewlines)
            if fallback.hasPrefix("https://") { fallback.removeFirst("https://".count) }
            if fallback.hasPrefix("http://") { fallback.removeFirst("http://".count) }
            fallback = fallback.split(separator: "/").first.map(String.init) ?? fallback
            fallback = fallback.split(separator: ":").first.map(String.init) ?? fallback
            return fallback
        }()
        return "http://\(host):\(informPort)/inform"
    }
}
