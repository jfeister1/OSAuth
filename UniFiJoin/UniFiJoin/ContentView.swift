import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appModel: AppViewModel

    var body: some View {
        ZStack {
            AtmosphereBackground()

            VStack(spacing: 0) {
                HeaderBar()
                Divider().overlay(AppTheme.panelStroke)
                HStack(spacing: 0) {
                    DeviceListView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Divider().overlay(AppTheme.panelStroke)

                    InspectorPanel()
                        .frame(width: 320)
                        .frame(maxHeight: .infinity)
                }
            }
        }
        .foregroundStyle(AppTheme.textPrimary)
        .task {
            await appModel.bootstrap()
        }
    }
}

private struct HeaderBar: View {
    @EnvironmentObject private var appModel: AppViewModel

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("UniFi Join")
                    .font(AppTheme.display)
                    .foregroundStyle(AppTheme.textPrimary)

                Text("Discover factory-default gear and join it to your current network.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer()

            ControllerPill()

            Button {
                Task { await appModel.scan() }
            } label: {
                Label(appModel.isScanning ? "Scanning…" : "Scan", systemImage: "radar")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .background(AppTheme.accentMuted, in: Capsule())
            .overlay(Capsule().stroke(AppTheme.accent.opacity(0.45), lineWidth: 1))
            .disabled(appModel.isScanning)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }
}

private struct ControllerPill: View {
    @EnvironmentObject private var appModel: AppViewModel

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(appModel.isControllerReady ? AppTheme.accent : AppTheme.warning)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(appModel.isControllerReady
                     ? (appModel.settings.siteName.isEmpty ? "Controller ready" : appModel.settings.siteName)
                     : "Controller not configured")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Text(appModel.settings.controllerHost.isEmpty ? "Open Settings to connect" : appModel.settings.controllerHost)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.panelStroke, lineWidth: 1)
        )
    }
}

private struct InspectorPanel: View {
    @EnvironmentObject private var appModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Join")
                .font(AppTheme.title)

            Text("Selected devices are pointed at \(appModel.settings.informURL) when needed, then adopted into your site via the UniFi Network API.")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                metric("Selected", "\(appModel.selectedDeviceIDs.count)")
                metric("Pending on controller", "\(appModel.pendingByMAC.count)")
                metric("LAN discoveries", "\(appModel.devices.count)")
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AppTheme.panelStroke, lineWidth: 1)
            )

            Toggle("Factory-default / pending only", isOn: $appModel.filterFactoryDefaultOnly)
                .toggleStyle(.switch)
                .font(.system(size: 12, weight: .medium))

            Button("Select adoptable") {
                appModel.selectAdoptable()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(AppTheme.accent)

            Spacer()

            if let error = appModel.errorMessage {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.danger)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.danger.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            } else if let status = appModel.statusMessage {
                Text(status)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Button {
                Task { await appModel.adoptSelected() }
            } label: {
                HStack {
                    Spacer()
                    if appModel.isAdopting {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(appModel.isAdopting ? "Joining…" : "Join selected to site")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Spacer()
                }
                .padding(.vertical, 12)
                .foregroundStyle(Color.black.opacity(0.85))
                .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(appModel.selectedDeviceIDs.isEmpty || !appModel.isControllerReady || appModel.isAdopting)
            .opacity(appModel.selectedDeviceIDs.isEmpty || !appModel.isControllerReady ? 0.45 : 1)
        }
        .padding(20)
        .background(AppTheme.panel.opacity(0.55))
    }

    private func metric(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
        }
    }
}
