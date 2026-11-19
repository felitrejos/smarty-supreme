import SwiftUI

struct GameCommands: Commands {
    let controller: HostController
    @Binding var showsFrameTimes: Bool

    private var match: Match {
        controller.match
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Game…", action: match.chooseNewGame)
                .keyboardShortcut("n")
                .disabled(controller.isViewer)
            Divider()
            Toggle("Use as Player B’s Screen", isOn: Binding(get: { controller.isViewer }, set: controller.setViewer))
                .disabled(!controller.isViewer && match.hasStarted && !match.isGameOver)
        }
        CommandMenu("Game") {
            Button(match.isPaused ? "Resume" : "Pause", action: match.togglePause)
                .keyboardShortcut(.escape, modifiers: [])
                .disabled(controller.isViewer || !match.hasStarted || match.isGameOver || match.isHeld || match.isWaitingForADevice)
            Button("Swap Sides", action: match.swapSides)
                .disabled(controller.isViewer || match.hasStarted)
            Divider()
            Toggle("Commentary", isOn: Bindable(match.referee).commentates)
                .disabled(controller.isViewer)
        }
        CommandGroup(before: .toolbar) {
            ForEach(CameraView.allCases, id: \.self) { camera in
                Toggle(camera.title, isOn: Binding(get: { match.camera == camera }, set: { if $0 { match.camera = camera } }))
                    .keyboardShortcut(camera.shortcut)
                    .disabled(controller.isViewer)
            }
            Divider()
            Toggle("Show Frame Times", isOn: $showsFrameTimes)
                .keyboardShortcut("f", modifiers: [.command, .option])
            Divider()
        }
        CommandGroup(replacing: .help) {
            Button("Controls", action: match.showControls)
        }
    }
}
