import SwiftUI

@main
struct FlickRecorderApp: App {
    @State private var library = RecordingLibrary()
    @State private var motion = MotionService()

    var body: some Scene {
        WindowGroup {
            SetupView(library: library, motion: motion)
        }
    }
}
