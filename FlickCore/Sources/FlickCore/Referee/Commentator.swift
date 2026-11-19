public struct CommentaryLine: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case call
        case highlight
        case opponent
    }

    public let text: String
    public let kind: Kind
    public let createdAt: Microseconds

    public init(text: String, kind: Kind, createdAt: Microseconds) {
        self.text = text
        self.kind = kind
        self.createdAt = createdAt
    }
}

public struct Commentator: Sendable {
    public static let smashStrength = 0.8
    public static let longRally = 10
    public static let staleAfter: Microseconds = 3_000_000
    public static let opponentLongRally = 8
    public static let opponentPlainPointChance = 0.8

    private struct Point {
        var rally = 0
        var lastHit: (side: Side, strength: Double)?
        var edgeBy: Side?
        var whiffBy: Side?
        var hasHighlight = false
    }

    private let names: [Side: String]
    private let config: GameConfig
    private let opponent: Side?
    private var random: SplitMix64
    private var lastSaid: [OpponentLine: Int] = [:]
    private var point = Point()
    private var queue: [CommentaryLine] = []

    public init(names: [Side: String], config: GameConfig = GameConfig(), opponent: Side? = nil, seed: UInt64 = 0) {
        self.names = names
        self.config = config
        self.opponent = opponent
        random = SplitMix64(seed: seed)
    }

    public mutating func observe(_ events: [GameEvent], at now: Microseconds) {
        let target = config.winningScore
        let winner = events.lazy.compactMap { if case .gameOver(let winner) = $0 { winner } else { nil } }.first
        let isForfeit = winner != nil && !events.contains { if case .pointScored = $0 { true } else { false } }
        if let winner, isForfeit {
            queue.append(CommentaryLine(text: Umpire.forfeit(name(winner)), kind: .call, createdAt: now))
        }
        for event in events {
            switch event {
            case .served:
                point.rally = 0
                point.lastHit = nil
                point.edgeBy = nil
                point.whiffBy = nil
            case .hit(let side, let strength, let rally):
                point.rally = rally
                point.lastHit = (side, strength)
                point.edgeBy = nil
                point.whiffBy = nil
                if rally == Self.longRally {
                    highlight(Umpire.longRally, at: now)
                }
            case .edgeHit(let side):
                point.edgeBy = side
            case .whiff(let side):
                point.whiffBy = side
            case .pointScored(let pointWinner, let score):
                if let opponent, let reaction = reaction(of: opponent, toPointWonBy: pointWinner, score: score, target: target, gameWinner: winner) {
                    queue.append(CommentaryLine(text: say(reaction), kind: .opponent, createdAt: now))
                }
                if let winner {
                    queue.append(CommentaryLine(text: Umpire.game(name(winner), score: score, target: target), kind: .call, createdAt: now))
                } else {
                    callPoint(won: pointWinner, score: score, target: target, at: now)
                }
                point = Point()
            case .wallBounce, .gameOver, .paused, .resumed:
                break
            }
        }
    }

    public mutating func next(at now: Microseconds, duringRally: Bool) -> CommentaryLine? {
        queue.removeAll { now - min(now, $0.createdAt) > Self.staleAfter }
        guard let index = queue.firstIndex(where: { !duringRally || $0.kind != .call }) else { return nil }
        return queue.remove(at: index)
    }

    private mutating func callPoint(won winner: Side, score: Score, target: Int, at now: Microseconds) {
        let server = score.server(firstServer: config.firstServer, target: target, servesPerTurn: config.servesPerTurn)
        queue.append(CommentaryLine(text: Umpire.call(score, server: server, target: target, name: name), kind: .call, createdAt: now))
        if let lastHit = point.lastHit, lastHit.side == winner, lastHit.strength > Self.smashStrength {
            highlight(Umpire.smash(name(winner)), at: now)
        }
        if let leader = leader(of: score), score[leader] >= target - 1, score[leader.opponent] < target - 1 {
            highlight(Umpire.matchPoint(name(leader)), at: now)
        }
    }

    private mutating func reaction(of me: Side, toPointWonBy winner: Side, score: Score, target: Int, gameWinner: Side?) -> OpponentLine? {
        if let gameWinner {
            return gameWinner == me ? .wonTheGame : .lostTheGame
        }
        if let leader = leader(of: score), score[leader] >= target - 1, score.a != score.b {
            return leader == me ? .hasMatchPoint : .facesMatchPoint
        }
        let iWon = winner == me
        if let whiffBy = point.whiffBy, whiffBy != winner {
            return iWon ? .theyWhiffed : .whiffed
        }
        if let lastHit = point.lastHit, lastHit.side == winner, lastHit.strength > Self.smashStrength {
            return iWon ? .smashWinner : .beatenBySmash
        }
        if !iWon, point.edgeBy == winner {
            return .beatenByEdge
        }
        if point.rally >= Self.opponentLongRally {
            return iWon ? .wonALongRally : .lostALongRally
        }
        guard Double.random(in: 0..<1, using: &random) < Self.opponentPlainPointChance else { return nil }
        return iWon ? .wonAPoint : .lostAPoint
    }

    private mutating func say(_ reaction: OpponentLine) -> String {
        let lines = reaction.lines
        var index = Int.random(in: 0..<lines.count, using: &random)
        if index == lastSaid[reaction] {
            index = (index + 1) % lines.count
        }
        lastSaid[reaction] = index
        return lines[index]
    }

    private mutating func highlight(_ text: String, at now: Microseconds) {
        guard !point.hasHighlight else { return }
        point.hasHighlight = true
        queue.append(CommentaryLine(text: text, kind: .highlight, createdAt: now))
    }

    private func leader(of score: Score) -> Side? {
        score.a == score.b ? nil : (score.a > score.b ? .playerA : .playerB)
    }

    private func name(_ side: Side) -> String {
        names[side] ?? side.playerName
    }
}
