import SwiftUI

@main
struct FlickHostApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Flick Pong")
                .font(.largeTitle.weight(.semibold))
                .frame(minWidth: 800, minHeight: 500)
        }
    }
}
