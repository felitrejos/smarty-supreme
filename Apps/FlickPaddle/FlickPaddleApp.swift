import SwiftUI

@main
struct FlickPaddleApp: App {
    @State private var motion = MotionService()

    var body: some Scene {
        WindowGroup {
            SensorTestView(motion: motion)
        }
    }
}
