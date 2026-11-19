import SmartyCore
import Testing

struct TouchInputTests {
    @Test(arguments: [
        (0.0, -80.0, true),
        (30.0, -80.0, true),
        (0.0, -40.0, false),
        (60.0, -70.0, false),
        (0.0, 80.0, false),
    ])
    func aShortUpwardSwipeIsASwing(across: Double, down: Double, isSwing: Bool) {
        #expect(TouchInput.isSwing(across: across, down: down) == isSwing)
    }

    @Test func aSwipeSwingsAtHalfStrengthAtTheTimeItEnds() {
        let swing = TouchInput.swing(at: 1_234)

        #expect(swing.peakTime == 1_234)
        #expect(swing.strength == 0.5)
    }

    @Test(arguments: [(-20.0, 0.0), (0.0, 0.0), (150.0, 0.5), (300.0, 1.0), (340.0, 1.0)])
    func draggingAcrossTheTrackSetsThePaddlePosition(x: Double, position: Double) {
        #expect(TouchInput.position(x: x, width: 300) == position)
    }
}
