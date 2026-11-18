import SwiftUI

@main
struct FlickHostApp: App {
    @State private var controller = HostController()
    @State private var stats = FrameStats()
    @AppStorage("showsFrameTimes") private var showsFrameTimes = false

    var body: some Scene {
        Window("Flick Pong", id: "game") {
            GameView(match: controller.match, stats: stats, showsFrameTimes: showsFrameTimes)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear(perform: controller.start)
        }
        .commands {
            GameCommands(match: controller.match, showsFrameTimes: $showsFrameTimes)
        }

        Window("iPhone Paddles", id: "paddles") {
            LobbyView(controller: controller)
                .frame(minWidth: 460, minHeight: 540)
                .onAppear(perform: controller.start)
        }
        .defaultSize(width: 520, height: 640)
        .keyboardShortcut("0")
    }
}
