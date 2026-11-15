public struct Score: Equatable, Sendable {
    public private(set) var a: Int
    public private(set) var b: Int

    public init(a: Int, b: Int) {
        self.a = a
        self.b = b
    }

    public subscript(side: Side) -> Int {
        side == .playerA ? a : b
    }

    mutating func award(_ side: Side) {
        if side == .playerA {
            a += 1
        } else {
            b += 1
        }
    }

    public func winner(target: Int) -> Side? {
        guard max(a, b) >= target, abs(a - b) >= 2 else { return nil }
        return a > b ? .playerA : .playerB
    }

    public func server(firstServer: Side, target: Int, servesPerTurn: Int) -> Side {
        let points = a + b
        let isDeuce = a >= target - 1 && b >= target - 1
        let turn = isDeuce ? points : points / servesPerTurn
        return turn.isMultiple(of: 2) ? firstServer : firstServer.opponent
    }
}

public struct Swing: Equatable, Sendable {
    public let side: Side
    public let step: UInt64
    public let strength: Double
    public let aim: Double

    public init(side: Side, step: UInt64, strength: Double, aim: Double) {
        precondition((0...1).contains(strength), "Strength must be between 0 and 1")
        precondition((-1...1).contains(aim), "Aim must be between -1 and 1")
        self.side = side
        self.step = step
        self.strength = strength
        self.aim = aim
    }
}

public enum GameCommand: Equatable, Sendable {
    case pause
    case resume
}

public struct StepInput: Sendable {
    public var targetA: Double?
    public var targetB: Double?
    public var swings: [Swing]
    public var command: GameCommand?

    public init(targetA: Double? = nil, targetB: Double? = nil, swings: [Swing] = [], command: GameCommand? = nil) {
        self.targetA = targetA
        self.targetB = targetB
        self.swings = swings
        self.command = command
    }
}

public enum GameEvent: Equatable, Sendable {
    case served(Side)
    case hit(Side, strength: Double, rally: Int)
    case whiff(Side)
    case wallBounce
    case pointScored(winner: Side, score: Score)
    case gameOver(winner: Side)
    case paused
    case resumed
}
