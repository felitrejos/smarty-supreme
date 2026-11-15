import SwiftUI

@main
struct FlickHostApp: App {
    @State private var controller = HostController()

    var body: some Scene {
        WindowGroup {
            LobbyView(controller: controller)
                .frame(minWidth: 820, minHeight: 420)
                .onAppear(perform: controller.start)
        }
    }
}
