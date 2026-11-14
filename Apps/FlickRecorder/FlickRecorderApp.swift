import SwiftUI

@main
struct FlickRecorderApp: App {
    @State private var library = RecordingLibrary()
    @State private var motion = MotionRecorder()

    var body: some Scene {
        WindowGroup {
            SetupView(library: library, motion: motion)
        }
    }
}
