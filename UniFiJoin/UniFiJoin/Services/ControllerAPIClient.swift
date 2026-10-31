import Foundation

enum ControllerAPIError: LocalizedError {
    case notConfigured
    case invalidURL
    case httpStatus(Int, String?)
    case decoding(Error)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Connect a UniFi Network console in Settings before adopting devices."
        case .invalidURL:
            return "Controller host is not a valid URL."
        case .httpStatus(let code, let body):
            if let body, !body.isEmpty {
                return "Controller returned HTTP \(code): \(body)"
            }
            return "Controller returned HTTP \(code)."
        case .decoding(let error):
            return "Unexpected controller response: \(error.localizedDescription)"
        case .transport(let error):
            return error.localizedDescription
        }
    }
}

actor ControllerAPIClient {
    private var settings: AppSettings
    private var session: URLSession
    private var preferredBaseURL: URL?

    init(settings: AppSettings) {
        self.settings = settings
        self.session = Self.makeSession(trustSelfSigned: settings.trustSelfSigned)
    }

    func updateSettings(_ settings: AppSettings) {
        let trustChanged = settings.trustSelfSigned != self.settings.trustSelfSigned
        self.settings = settings
        if trustChanged {
            self.session = Self.makeSession(trustSelfSigned: settings.trustSelfSigned)
        }
        preferredBaseURL = nil
    }

    func fetchInfo() async throws -> ControllerInfo {
        let payload: InfoResponse = try await get("/v1/info")
        return ControllerInfo(
            applicationName: payload.applicationName ?? payload.name,
            version: payload.version ?? payload.applicationVersion
        )
    }

    func fetchSites() async throws -> [ControllerSite] {
        let page: PageResponse<SiteDTO> = try await get("/v1/sites?limit=200")
        return page.data.map { ControllerSite(id: $0.id, name: $0.name ?? $0.id) }
    }

    func fetchPendingDevices() async throws -> [PendingDevice] {
        let page: PageResponse<PendingDeviceDTO> = try await get("/v1/pending-devices?limit=200")
        return page.data.map {
            PendingDevice(
                macAddress: normalizeMAC($0.macAddress ?? $0.mac ?? ""),
                ipAddress: $0.ipAddress ?? $0.ip,
                model: $0.model,
                firmwareVersion: $0.firmwareVersion ?? $0.version,
                state: $0.state,
                supported: $0.supported,
                adoptionTargetSiteIds: $0.adoptionTargetSiteIds ?? []
            )
        }
        .filter { !$0.macAddress.isEmpty }
    }

    func adopt(macAddress: String, siteID: String) async throws {
        struct Body: Encodable {
            let macAddress: String
            let ignoreDeviceLimit: Bool
        }

        let normalized = normalizeMAC(macAddress)
        do {
            let _: EmptyResponse = try await post(
                "/v1/sites/\(siteID)/devices",
                body: Body(macAddress: normalized, ignoreDeviceLimit: true)
            )
        } catch {
            struct LegacyBody: Encodable {
                let mac: String
                let siteId: String
            }
            let _: EmptyResponse = try await post(
                "/v1/pending-devices",
                body: LegacyBody(mac: normalized, siteId: siteID)
            )
        }
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        try await sendWithBaseFallback { base in
            try makeRequest(path: path, method: "GET", base: base)
        }
    }

    private func post<Body: Encodable, T: Decodable>(_ path: String, body: Body) async throws -> T {
        try await sendWithBaseFallback { base in
            var request = try makeRequest(path: path, method: "POST", base: base)
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            return request
        }
    }

    private func makeRequest(path: String, method: String, base: URL) throws -> URLRequest {
        guard settings.isConfigured else { throw ControllerAPIError.notConfigured }
        guard let url = URL(string: path, relativeTo: base)?.absoluteURL else {
            throw ControllerAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(settings.apiKey, forHTTPHeaderField: "X-API-KEY")
        request.setValue(settings.apiKey, forHTTPHeaderField: "X-API-Key")
        return request
    }

    private func sendWithBaseFallback<T: Decodable>(
        requestBuilder: (URL) throws -> URLRequest
    ) async throws -> T {
        let bases: [URL]
        if let preferredBaseURL {
            bases = [preferredBaseURL]
                + settings.integrationBaseURLCandidates.filter { $0 != preferredBaseURL }
        } else {
            bases = settings.integrationBaseURLCandidates
        }
        guard !bases.isEmpty else { throw ControllerAPIError.invalidURL }

        var lastError: Error = ControllerAPIError.invalidURL
        for base in bases {
            do {
                let request = try requestBuilder(base)
                let value: T = try await perform(request)
                preferredBaseURL = base
                return value
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ControllerAPIError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ControllerAPIError.httpStatus(-1, nil)
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw ControllerAPIError.httpStatus(http.statusCode, body)
        }

        if T.self == EmptyResponse.self || data.isEmpty {
            return EmptyResponse() as! T
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ControllerAPIError.decoding(error)
        }
    }

    private func normalizeMAC(_ value: String) -> String {
        let hex = value.lowercased().filter(\.isHexDigit)
        guard hex.count == 12 else { return value.lowercased() }
        var parts: [String] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            parts.append(String(hex[index..<next]))
            index = next
        }
        return parts.joined(separator: ":")
    }

    private static func makeSession(trustSelfSigned: Bool) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = true
        if trustSelfSigned {
            return URLSession(
                configuration: config,
                delegate: InsecureTrustDelegate(),
                delegateQueue: nil
            )
        }
        return URLSession(configuration: config)
    }
}

private final class InsecureTrustDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

private struct PageResponse<T: Decodable>: Decodable {
    var data: [T]
    var count: Int?
    var totalCount: Int?
}

private struct SiteDTO: Decodable {
    var id: String
    var name: String?
}

private struct PendingDeviceDTO: Decodable {
    var macAddress: String?
    var mac: String?
    var ipAddress: String?
    var ip: String?
    var model: String?
    var firmwareVersion: String?
    var version: String?
    var state: String?
    var supported: Bool?
    var adoptionTargetSiteIds: [String]?
}

private struct InfoResponse: Decodable {
    var applicationName: String?
    var name: String?
    var version: String?
    var applicationVersion: String?
}

private struct EmptyResponse: Decodable {}
