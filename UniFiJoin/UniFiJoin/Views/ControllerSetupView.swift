import SwiftUI

struct ControllerSetupView: View {
    @EnvironmentObject private var appModel: AppViewModel
    @State private var draft: AppSettings = .default
    @State private var isTesting = false

    var body: some View {
        Form {
            Section("UniFi Network console") {
                TextField("Host or IP", text: $draft.controllerHost)
                    .textFieldStyle(.roundedBorder)
                SecureField("API key", text: $draft.apiKey)
                    .textFieldStyle(.roundedBorder)
                Toggle("Use HTTPS", isOn: $draft.useHTTPS)
                Toggle("Trust self-signed certificate", isOn: $draft.trustSelfSigned)

                if !appModel.sites.isEmpty {
                    Picker("Site", selection: $draft.siteID) {
                        ForEach(appModel.sites) { site in
                            Text(site.name).tag(site.id)
                        }
                    }
                } else {
                    TextField("Site ID", text: $draft.siteID)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Section("Layer-3 inform") {
                TextField("Inform host", text: $draft.informHost)
                    .textFieldStyle(.roundedBorder)
                TextField("Inform port", value: $draft.informPort, format: .number)
                    .textFieldStyle(.roundedBorder)
                Text(draft.informURL)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Section("Factory-default SSH") {
                TextField("Username", text: $draft.sshUsername)
                    .textFieldStyle(.roundedBorder)
                SecureField("Password", text: $draft.sshPassword)
                    .textFieldStyle(.roundedBorder)
                Text("Used only when a discovered device is not yet pending on the controller.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Scan on launch", isOn: $draft.autoScanOnLaunch)

                HStack {
                    Button("Test connection") {
                        Task { await testConnection() }
                    }
                    .disabled(isTesting || draft.controllerHost.isEmpty || draft.apiKey.isEmpty)

                    Spacer()

                    Button("Save") {
                        Task { await persist() }
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }

            if let info = appModel.controllerInfo {
                Section("Status") {
                    LabeledContent("Application", value: info.applicationName ?? "UniFi Network")
                    LabeledContent("Version", value: info.version ?? "—")
                }
            }

            if let error = appModel.errorMessage {
                Section {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            appModel.suggestControllerFromDiscovery()
            draft = appModel.settings
        }
        .onChange(of: draft.siteID) { _, newValue in
            draft.siteName = appModel.sites.first(where: { $0.id == newValue })?.name ?? draft.siteName
        }
    }

    private func persist() async {
        if let selected = appModel.sites.first(where: { $0.id == draft.siteID }) {
            draft.siteName = selected.name
        }
        await appModel.saveSettings(draft)
    }

    private func testConnection() async {
        isTesting = true
        defer { isTesting = false }
        await persist()
    }
}
