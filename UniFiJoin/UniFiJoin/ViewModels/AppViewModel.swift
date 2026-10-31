import Foundation
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    @Published var settings: AppSettings
    @Published var devices: [DiscoveredDevice] = []
    @Published var pendingByMAC: [String: PendingDevice] = [:]
    @Published var sites: [ControllerSite] = []
    @Published var controllerInfo: ControllerInfo?
    @Published var selectedDeviceIDs: Set<String> = []
    @Published var adoptionStatus: [String: AdoptionStatus] = [:]
    @Published var adoptionMessages: [String: String] = [:]
    @Published var isScanning = false
    @Published var isRefreshingController = false
    @Published var isAdopting = false
    @Published var statusMessage: String?
    @Published var errorMessage: String?
    @Published var filterFactoryDefaultOnly = false

    private let discovery = DiscoveryService()
    private var api: ControllerAPIClient
    private var adoption: AdoptionService

    init() {
        let loaded = CredentialsStore.load()
        self.settings = loaded
        let client = ControllerAPIClient(settings: loaded)
        self.api = client
        self.adoption = AdoptionService(api: client)
    }

    var isControllerReady: Bool {
        settings.isConfigured && !settings.siteID.isEmpty
    }

    var visibleDevices: [DiscoveredDevice] {
        let merged = mergePendingOnlyDevices(into: devices)
        if filterFactoryDefaultOnly {
            return merged.filter(\.isLikelyAdoptable)
        }
        return merged
    }

    var selectedDevices: [DiscoveredDevice] {
        visibleDevices.filter { selectedDeviceIDs.contains($0.id) }
    }

    func bootstrap() async {
        if settings.autoScanOnLaunch {
            await scan()
        }
        if settings.isConfigured {
            await refreshController()
        }
    }

    func saveSettings(_ newSettings: AppSettings) async {
        settings = newSettings
        do {
            try CredentialsStore.save(newSettings)
            await api.updateSettings(newSettings)
            statusMessage = "Controller settings saved."
            errorMessage = nil
            await refreshController()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func scan() async {
        isScanning = true
        errorMessage = nil
        defer { isScanning = false }

        do {
            let found = try await discovery.scan()
            devices = found
            statusMessage = "Found \(found.count) UniFi device\(found.count == 1 ? "" : "s") on the LAN."
            if settings.isConfigured {
                await refreshPending()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshController() async {
        guard settings.isConfigured else {
            controllerInfo = nil
            sites = []
            pendingByMAC = [:]
            return
        }

        isRefreshingController = true
        defer { isRefreshingController = false }

        do {
            await api.updateSettings(settings)
            async let info = api.fetchInfo()
            async let siteList = api.fetchSites()
            async let pending = api.fetchPendingDevices()

            controllerInfo = try await info
            sites = try await siteList
            pendingByMAC = Dictionary(uniqueKeysWithValues: try await pending.map { ($0.id, $0) })

            if settings.siteID.isEmpty, let first = sites.first {
                var updated = settings
                updated.siteID = first.id
                updated.siteName = first.name
                settings = updated
                try? CredentialsStore.save(updated)
            } else if let match = sites.first(where: { $0.id == settings.siteID }) {
                settings.siteName = match.name
            }

            statusMessage = "Connected to \(controllerInfo?.applicationName ?? "UniFi Network")\(controllerInfo?.version.map { " \($0)" } ?? "")."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshPending() async {
        guard settings.isConfigured else { return }
        do {
            await api.updateSettings(settings)
            let pending = try await api.fetchPendingDevices()
            pendingByMAC = Dictionary(uniqueKeysWithValues: pending.map { ($0.id, $0) })
        } catch {
            // Soft-fail during LAN scans; connection issues surface on explicit refresh.
        }
    }

    func toggleSelection(_ device: DiscoveredDevice) {
        if selectedDeviceIDs.contains(device.id) {
            selectedDeviceIDs.remove(device.id)
        } else {
            selectedDeviceIDs.insert(device.id)
        }
    }

    func selectAdoptable() {
        selectedDeviceIDs = Set(
            visibleDevices.filter { pendingByMAC[$0.id] != nil || $0.isFactoryDefault == true }.map(\.id)
        )
    }

    func adoptSelected(forceSetInform: Bool = false) async {
        let targets = selectedDevices
        guard !targets.isEmpty else { return }
        guard isControllerReady else {
            errorMessage = "Configure your UniFi console and site in Settings first."
            return
        }

        isAdopting = true
        defer { isAdopting = false }

        var successCount = 0
        for device in targets {
            adoptionStatus[device.id] = pendingByMAC[device.id] == nil ? .settingInform : .adopting
            let result = await adoption.join(
                device: device,
                pending: pendingByMAC[device.id],
                settings: settings,
                forceSetInform: forceSetInform || device.isFactoryDefault == true
            )
            adoptionStatus[device.id] = result.status
            if let message = result.message {
                adoptionMessages[device.id] = message
            }
            if result.status == .succeeded {
                successCount += 1
            }
        }

        await refreshPending()
        statusMessage = "Join complete: \(successCount) of \(targets.count) succeeded."
    }

    func suggestControllerFromDiscovery() {
        guard settings.controllerHost.isEmpty else { return }
        let consoleHints = ["UDM", "UDR", "UCG", "UXG", "UCK", "CloudKey", "Gateway"]
        if let console = devices.first(where: { device in
            let blob = "\(device.model ?? "") \(device.platform ?? "") \(device.hostname ?? "")".uppercased()
            return consoleHints.contains(where: { blob.contains($0) })
        }), let ip = console.ipAddress {
            settings.controllerHost = ip
            if settings.informHost.isEmpty {
                settings.informHost = ip
            }
        }
    }

    private func mergePendingOnlyDevices(into lanDevices: [DiscoveredDevice]) -> [DiscoveredDevice] {
        var byMAC = Dictionary(uniqueKeysWithValues: lanDevices.map { ($0.id, $0) })
        for pending in pendingByMAC.values where byMAC[pending.id] == nil {
            byMAC[pending.id] = DiscoveredDevice(
                macAddress: pending.macAddress,
                ipAddress: pending.ipAddress,
                hostname: nil,
                platform: nil,
                model: pending.model,
                firmware: pending.firmwareVersion,
                isFactoryDefault: true,
                uptimeSeconds: nil,
                sshPort: nil,
                lastSeen: .now,
                sourceAddress: pending.ipAddress ?? "controller"
            )
        }
        return byMAC.values.sorted {
            ($0.hostname ?? $0.macAddress)
                .localizedCaseInsensitiveCompare($1.hostname ?? $1.macAddress) == .orderedAscending
        }
    }
}
