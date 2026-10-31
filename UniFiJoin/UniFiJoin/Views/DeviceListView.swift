import SwiftUI

struct DeviceListView: View {
    @EnvironmentObject private var appModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Devices")
                    .font(AppTheme.title)
                Spacer()
                if appModel.isScanning || appModel.isRefreshingController {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 10)

            if appModel.visibleDevices.isEmpty {
                emptyState
            } else {
                List(selection: $appModel.selectedDeviceIDs) {
                    ForEach(appModel.visibleDevices) { device in
                        DeviceRowView(
                            device: device,
                            pending: appModel.pendingByMAC[device.id],
                            status: appModel.adoptionStatus[device.id] ?? .idle,
                            message: appModel.adoptionMessages[device.id]
                        )
                        .tag(device.id)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 6, leading: 18, bottom: 6, trailing: 18))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(AppTheme.accent.opacity(0.8))
                .symbolEffect(.pulse, options: .repeating, isActive: appModel.isScanning)

            Text(appModel.isScanning ? "Listening on UDP/10001…" : "No UniFi devices yet")
                .font(.system(size: 16, weight: .semibold, design: .rounded))

            Text("Connect this Mac to the same Layer-2 network as your gear, then scan. Factory-default devices answer the Ubiquiti discovery probe.")
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            Button("Scan network") {
                Task { await appModel.scan() }
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

struct DeviceRowView: View {
    let device: DiscoveredDevice
    let pending: PendingDevice?
    let status: AdoptionStatus
    let message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(device.displayName)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))

                Spacer()

                statusChip
            }

            HStack(spacing: 16) {
                labeled("MAC", device.macAddress)
                labeled("IP", device.ipAddress ?? "—")
                labeled("Model", device.modelLabel)
            }

            HStack(spacing: 16) {
                labeled("Firmware", device.firmware ?? pending?.firmwareVersion ?? "—")
                labeled("State", pending?.state ?? device.statusLabel)
            }

            if let message {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(status == .failed ? AppTheme.danger : AppTheme.textSecondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    pending != nil ? AppTheme.accent.opacity(0.45) : AppTheme.panelStroke,
                    lineWidth: 1
                )
        )
    }

    private var statusChip: some View {
        Text(chipLabel)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(chipForeground)
            .background(chipForeground.opacity(0.15), in: Capsule())
    }

    private var chipLabel: String {
        if status != .idle { return status.label }
        if pending != nil { return "Pending adoption" }
        return device.statusLabel
    }

    private var chipForeground: Color {
        switch status {
        case .succeeded: return AppTheme.accent
        case .failed: return AppTheme.danger
        case .settingInform, .adopting: return AppTheme.warning
        case .idle:
            return pending != nil || device.isFactoryDefault == true ? AppTheme.accent : AppTheme.textSecondary
        }
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.textSecondary)
            Text(value)
                .font(AppTheme.mono)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
