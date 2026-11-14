import FlickCore
import SwiftUI
import UIKit

struct HoldSurface: UIViewRepresentable {
    let onPress: (Microseconds) -> Void
    let onRelease: (Microseconds) -> Void

    func makeUIView(context: Context) -> TouchView {
        TouchView()
    }

    func updateUIView(_ view: TouchView, context: Context) {
        view.onPress = onPress
        view.onRelease = onRelease
    }

    final class TouchView: UIView {
        var onPress: (Microseconds) -> Void = { _ in }
        var onRelease: (Microseconds) -> Void = { _ in }

        override init(frame: CGRect) {
            super.init(frame: frame)
            isMultipleTouchEnabled = false
        }

        required init?(coder: NSCoder) {
            fatalError("TouchView is only created in code")
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            onPress(microseconds(sinceBoot: touches.first!.timestamp))
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            onRelease(microseconds(sinceBoot: touches.first!.timestamp))
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            onRelease(microseconds(sinceBoot: touches.first!.timestamp))
        }
    }
}
