import SwiftUI

struct GameCommands: Commands {
    let match: Match
    @Binding var showsFrameTimes: Bool

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Game…", action: match.chooseNewGame)
                .keyboardShortcut("n")
        }
        CommandMenu("Game") {
            Button(match.isPaused ? "Resume" : "Pause", action: match.togglePause)
                .keyboardShortcut(.escape, modifiers: [])
                .disabled(match.isGameOver || match.isChoosingNewGame)
        }
        CommandGroup(before: .toolbar) {
            ForEach(CameraView.allCases, id: \.self) { camera in
                Toggle(camera.title, isOn: Binding(get: { match.camera == camera }, set: { if $0 { match.camera = camera } }))
                    .keyboardShortcut(camera.shortcut)
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
