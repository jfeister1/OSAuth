import Foundation

struct DiscoveredDevice: Identifiable, Hashable, Sendable {
    var id: String { macAddress.lowercased() }

    var macAddress: String
    var ipAddress: String?
    var hostname: String?
    var platform: String?
    var model: String?
    var firmware: String?
    var isFactoryDefault: Bool?
    var uptimeSeconds: UInt32?
    var sshPort: UInt16?
    var lastSeen: Date
    var sourceAddress: String

    var displayName: String {
        if let hostname, !hostname.isEmpty { return hostname }
        if let model, !model.isEmpty { return model }
        if let platform, !platform.isEmpty { return platform }
        return macAddress
    }

    var modelLabel: String {
        model ?? platform ?? "UniFi device"
    }

    var statusLabel: String {
        if isFactoryDefault == true { return "Factory default" }
        if isFactoryDefault == false { return "Managed / adopted" }
        return "Discovered"
    }

    var isLikelyAdoptable: Bool {
        isFactoryDefault != false
    }
}

struct PendingDevice: Identifiable, Hashable, Sendable {
    var id: String { macAddress.lowercased() }

    var macAddress: String
    var ipAddress: String?
    var model: String?
    var firmwareVersion: String?
    var state: String?
    var supported: Bool?
    var adoptionTargetSiteIds: [String]
}

struct ControllerSite: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
}

struct ControllerInfo: Hashable, Sendable {
    var applicationName: String?
    var version: String?
}

enum AdoptionStatus: String, Hashable, Sendable {
    case idle
    case settingInform
    case adopting
    case succeeded
    case failed

    var label: String {
        switch self {
        case .idle: return "Ready"
        case .settingInform: return "Setting inform…"
        case .adopting: return "Adopting…"
        case .succeeded: return "Joined"
        case .failed: return "Failed"
        }
    }
}
