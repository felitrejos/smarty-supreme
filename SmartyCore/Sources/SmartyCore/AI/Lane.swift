public enum Lane: CaseIterable, Sendable {
    case left
    case middle
    case right

    public init(x: Double, config: GameConfig) {
        let third = config.tableWidth / 3
        self = x < third ? .left : (x < 2 * third ? .middle : .right)
    }

    public func centre(in config: GameConfig) -> Double {
        let third = config.tableWidth / 3
        switch self {
        case .left: return third / 2
        case .middle: return third * 1.5
        case .right: return third * 2.5
        }
    }
}
