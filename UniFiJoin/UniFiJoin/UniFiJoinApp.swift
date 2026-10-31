import SwiftUI

@main
struct UniFiJoinApp: App {
    @StateObject private var appModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
                .frame(minWidth: 920, minHeight: 620)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1080, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Devices") {
                Button("Scan Network") {
                    Task { await appModel.scan() }
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("Adopt Selected") {
                    Task { await appModel.adoptSelected() }
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(appModel.selectedDeviceIDs.isEmpty || !appModel.isControllerReady)
            }
        }

        Settings {
            ControllerSetupView()
                .environmentObject(appModel)
                .frame(width: 480, height: 520)
        }
    }
}
