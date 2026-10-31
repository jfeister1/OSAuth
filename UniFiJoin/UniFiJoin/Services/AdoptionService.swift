import Foundation

struct AdoptionResult: Sendable {
    var macAddress: String
    var status: AdoptionStatus
    var message: String?
}

actor AdoptionService {
    private let api: ControllerAPIClient
    private let inform = InformService()

    init(api: ControllerAPIClient) {
        self.api = api
    }

    func join(
        device: DiscoveredDevice,
        pending: PendingDevice?,
        settings: AppSettings,
        forceSetInform: Bool
    ) async -> AdoptionResult {
        let mac = device.macAddress
        guard settings.isConfigured, !settings.siteID.isEmpty else {
            return AdoptionResult(
                macAddress: mac,
                status: .failed,
                message: "Choose a controller site in Settings."
            )
        }

        let needsInform = forceSetInform || pending == nil
        if needsInform {
            do {
                try await inform.setInform(
                    on: device,
                    informURL: settings.informURL,
                    username: settings.sshUsername,
                    password: settings.sshPassword
                )
            } catch {
                // If the device is already pending, continue to adopt.
                if pending == nil {
                    return AdoptionResult(
                        macAddress: mac,
                        status: .failed,
                        message: error.localizedDescription
                    )
                }
            }

            // Give the controller a moment to notice the inform.
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        }

        do {
            try await api.adopt(macAddress: mac, siteID: settings.siteID)
            return AdoptionResult(
                macAddress: mac,
                status: .succeeded,
                message: "Adoption requested for \(settings.siteName.isEmpty ? settings.siteID : settings.siteName)."
            )
        } catch {
            return AdoptionResult(
                macAddress: mac,
                status: .failed,
                message: error.localizedDescription
            )
        }
    }
}
