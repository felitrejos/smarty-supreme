import FlickCore
import SwiftUI

extension Side {
    var rubberColor: Color {
        self == .playerA ? Color(red: 0.72, green: 0.1, blue: 0.08) : Color(red: 0.08, green: 0.08, blue: 0.08)
    }
}
