import FlickCore
import SwiftUI

@main
struct FlickPaddleApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var motion: MotionService
    @State private var controller: PaddleController

    init() {
        let motion = MotionService()
        _motion = State(initialValue: motion)
        _controller = State(initialValue: PaddleController(motion: motion, launchedAt: SystemClock().now))
    }

    var body: some Scene {
        WindowGroup {
            PaddleView(controller: controller, isMotionAvailable: motion.isAvailable)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active: controller.start()
            case .background: controller.stop(.backgrounded)
            default: break
            }
        }
    }
}
