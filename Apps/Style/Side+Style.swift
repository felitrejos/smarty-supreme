import FlickCore
import SwiftUI

extension Side {
    var playerName: String {
        self == .playerA ? "Player A" : "Player B"
    }

    var rubberColor: Color {
        self == .playerA ? Color(red: 0.12, green: 0.36, blue: 0.86) : Color(red: 0.84, green: 0.16, blue: 0.16)
    }
}
