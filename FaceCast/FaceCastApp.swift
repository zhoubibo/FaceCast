import SwiftUI

@main
struct FaceCastApp: App {
    @StateObject private var coordinator = RecordingCoordinator()
    @StateObject private var permissions = PermissionManager()

    var body: some Scene {
        WindowGroup("FaceCast") {
            ControlPanelView(coordinator: coordinator, permissions: permissions)
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView(coordinator: coordinator)
        }

        MenuBarExtra {
            MenuBarView(coordinator: coordinator)
        } label: {
            if coordinator.isRecording {
                Text("● \(coordinator.elapsedTimeString)")
            } else {
                Image(systemName: "video.circle")
            }
        }
    }
}
