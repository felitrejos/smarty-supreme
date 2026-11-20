import Foundation

public enum HapticKind: UInt8, Sendable {
    case hit
    case miss
    case point
    case win
}

public enum ByeReason: UInt8, Sendable {
    case left
    case backgrounded
    case versionMismatch
    case gameFull
}

public enum Side: UInt8, CaseIterable, Sendable {
    case playerA
    case playerB
}

public enum GamePhase: UInt8, Sendable {
    case lobby
    case calibrating
    case ready
    case serving
    case rally
    case pointScored
    case paused
    case gameOver
}

public struct SwingMessage: Equatable, Sendable {
    public let peakAt: Microseconds
    public let strength: Float
    public let direction: SIMD3<Float>

    public init(peakAt: Microseconds, strength: Float, direction: SIMD3<Float>) {
        self.peakAt = peakAt
        self.strength = strength
        self.direction = direction
    }
}

public struct GameStateUpdate: Equatable, Sendable {
    public let phase: GamePhase
    public let scoreA: UInt8
    public let scoreB: UInt8
    public let side: Side
    public let serving: Side
    public let canResume: Bool
    public let connectionIsSlow: Bool
    public let winner: Side?

    public init(
        phase: GamePhase,
        scoreA: UInt8,
        scoreB: UInt8,
        side: Side,
        serving: Side,
        canResume: Bool,
        connectionIsSlow: Bool,
        winner: Side?
    ) {
        self.phase = phase
        self.scoreA = scoreA
        self.scoreB = scoreB
        self.side = side
        self.serving = serving
        self.canResume = canResume
        self.connectionIsSlow = connectionIsSlow
        self.winner = winner
    }
}

public struct TableSnapshot: Equatable, Sendable {
    public let step: UInt64
    public let ball: SIMD3<Float>
    public let velocity: SIMD3<Float>
    public let spin: SIMD3<Float>
    public let paddleA: Float
    public let paddleB: Float
    public let phase: GamePhase
    public let scoreA: UInt8
    public let scoreB: UInt8
    public let serving: Side
    public let rally: UInt32
    public let winner: Side?

    public init(
        step: UInt64,
        ball: SIMD3<Float>,
        velocity: SIMD3<Float>,
        spin: SIMD3<Float>,
        paddleA: Float,
        paddleB: Float,
        phase: GamePhase,
        scoreA: UInt8,
        scoreB: UInt8,
        serving: Side,
        rally: UInt32,
        winner: Side?
    ) {
        self.step = step
        self.ball = ball
        self.velocity = velocity
        self.spin = spin
        self.paddleA = paddleA
        self.paddleB = paddleB
        self.phase = phase
        self.scoreA = scoreA
        self.scoreB = scoreB
        self.serving = serving
        self.rally = rally
        self.winner = winner
    }
}

public struct RacketMessage: Equatable, Sendable {
    public let sampledAt: Microseconds
    public let orientation: SIMD4<Float>
    public let angularVelocity: SIMD3<Float>
    public let linearVelocity: SIMD3<Float>
    public let reach: SIMD3<Float>

    public init(sampledAt: Microseconds, orientation: SIMD4<Float>, angularVelocity: SIMD3<Float>, linearVelocity: SIMD3<Float>, reach: SIMD3<Float>) {
        self.sampledAt = sampledAt
        self.orientation = orientation
        self.angularVelocity = angularVelocity
        self.linearVelocity = linearVelocity
        self.reach = reach
    }
}

public enum Message: Equatable, Sendable {
    case hello(name: String)
    case helloAck(name: String)
    case calibrated(Handedness)
    case pointer(position: Float)
    case swing(SwingMessage)
    case ready(Bool)
    case ping
    case pong(pingSentAt: Microseconds, receivedAt: Microseconds)
    case haptic(HapticKind)
    case gameState(GameStateUpdate)
    case bye(ByeReason)
    case viewerHello(name: String)
    case pause(Bool)
    case snapshot(TableSnapshot)
    case racket(RacketMessage)
    case incoming(contactAt: Microseconds)
    case toss

    public var channel: Channel {
        switch self {
        case .pointer, .racket, .ping, .pong, .snapshot: .unreliable
        default: .reliable
        }
    }
}

public struct Packet: Equatable, Sendable {
    public let sequence: UInt32
    public let sentAt: Microseconds
    public let message: Message

    public init(sequence: UInt32, sentAt: Microseconds, message: Message) {
        self.sequence = sequence
        self.sentAt = sentAt
        self.message = message
    }
}

public enum MessageDecodingError: Error, Equatable {
    case truncated
    case otherVersion(UInt8)
    case unknownType(UInt8)
    case invalidPayload
}

public enum SequenceNumber {
    public static func isNewer(_ candidate: UInt32, than reference: UInt32) -> Bool {
        Int32(bitPattern: candidate &- reference) > 0
    }
}
