import SwiftUI

@main
struct SmartyHostApp: App {
    @State private var controller = HostController()
    @State private var stats = FrameStats()
    @AppStorage("showsFrameTimes") private var showsFrameTimes = false

    var body: some Scene {
        Window("Smarty Supreme", id: "game") {
            Group {
                switch controller.role {
                case .host:
                    GameView(match: controller.match, stats: stats, showsFrameTimes: showsFrameTimes)
                case .viewer(let viewer):
                    ViewerView(viewer: viewer, stats: stats, showsFrameTimes: showsFrameTimes)
                }
            }
            .overlay(alignment: .topTrailing) {
                SettingsButton(controller: controller, showsFrameTimes: $showsFrameTimes)
            }
            .frame(minWidth: 900, minHeight: 600)
            .onAppear(perform: controller.start)
        }
        .commands {
            GameCommands(controller: controller, showsFrameTimes: $showsFrameTimes)
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
