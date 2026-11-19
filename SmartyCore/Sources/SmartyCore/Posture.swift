import Foundation
import simd

extension MotionSample {
    public var uprightness: Double {
        -gravity.y / simd_length(gravity)
    }

    public var rollDegrees: Double {
        atan2(gravity.x, -gravity.y) * 180 / .pi
    }
}
