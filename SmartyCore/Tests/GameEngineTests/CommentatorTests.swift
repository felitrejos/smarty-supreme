import SmartyCore
import Testing

struct CommentatorTests {
    private let names: [Side: String] = [.playerA: "Player A", .playerB: "Computer"]

    @Test(arguments: [
        (Score(a: 1, b: 0), "One, love."),
        (Score(a: 2, b: 1), "One, two."),
        (Score(a: 7, b: 5), "Seven, five."),
        (Score(a: 4, b: 4), "Four all."),
        (Score(a: 10, b: 10), "Deuce."),
        (Score(a: 11, b: 10), "Advantage, Player A."),
        (Score(a: 12, b: 13), "Advantage, Computer."),
    ])
    func eachPointIsCalledLikeAnUmpireWithTheServersScoreFirst(score: Score, call: String) {
        var commentator = Commentator(names: names)
        commentator.observe([.pointScored(winner: .playerA, score: score)], at: 0)

        #expect(commentator.next(at: 0, duringRally: false)?.text == call)
    }

    @Test func aSmashWinnerIsAHighlightAfterTheCall() {
        var commentator = Commentator(names: names)
        commentator.observe([.hit(.playerA, strength: 0.9, rally: 3)], at: 0)
        commentator.observe([.pointScored(winner: .playerA, score: Score(a: 2, b: 1))], at: 0)

        #expect(commentator.next(at: 0, duringRally: false)?.kind == .call)
        #expect(commentator.next(at: 0, duringRally: false) == CommentaryLine(text: "Smash winner, Player A!", kind: .highlight, createdAt: 0))
        #expect(commentator.next(at: 0, duringRally: false) == nil)
    }

    @Test func aSmashThatComesBackIsNotAWinner() {
        var commentator = Commentator(names: names)
        commentator.observe([.hit(.playerA, strength: 0.9, rally: 3)], at: 0)
        commentator.observe([.hit(.playerB, strength: 0.4, rally: 4)], at: 0)
        commentator.observe([.pointScored(winner: .playerB, score: Score(a: 1, b: 2))], at: 0)

        #expect(commentator.next(at: 0, duringRally: false)?.kind == .call)
        #expect(commentator.next(at: 0, duringRally: false) == nil)
    }

    @Test func aRallyOfTenIsAHighlightSpokenDuringTheRally() {
        var commentator = Commentator(names: names)
        for rally in 1...12 {
            commentator.observe([.hit(rally.isMultiple(of: 2) ? .playerB : .playerA, strength: 0.5, rally: rally)], at: 0)
        }

        #expect(commentator.next(at: 0, duringRally: true)?.text == "What a rally!")
        #expect(commentator.next(at: 0, duringRally: true) == nil)
    }

    @Test func eachPointGetsAtMostOneCallAndOneHighlight() {
        var commentator = Commentator(names: names)
        for rally in 1...10 {
            commentator.observe([.hit(rally.isMultiple(of: 2) ? .playerB : .playerA, strength: 0.9, rally: rally)], at: 0)
        }
        commentator.observe([.pointScored(winner: .playerB, score: Score(a: 3, b: 10))], at: 0)

        let lines = [commentator.next(at: 0, duringRally: false), commentator.next(at: 0, duringRally: false), commentator.next(at: 0, duringRally: false)]
        #expect(lines.compactMap(\.?.kind) == [.highlight, .call])
    }

    @Test(arguments: [(Score(a: 10, b: 9), "Match point, Player A."), (Score(a: 4, b: 10), "Match point, Computer.")])
    func matchPointIsAHighlight(score: Score, highlight: String) {
        var commentator = Commentator(names: names)
        commentator.observe([.pointScored(winner: score.a > score.b ? .playerA : .playerB, score: score)], at: 0)
        _ = commentator.next(at: 0, duringRally: false)

        #expect(commentator.next(at: 0, duringRally: false)?.text == highlight)
    }

    @Test(arguments: [(Score(a: 6, b: 11), "Game, Computer. Eleven, six."), (Score(a: 12, b: 14), "Game, Computer.")])
    func theGameEndIsOneCall(score: Score, call: String) {
        var commentator = Commentator(names: names)
        commentator.observe([.pointScored(winner: .playerB, score: score), .gameOver(winner: .playerB)], at: 0)

        #expect(commentator.next(at: 0, duringRally: false)?.text == call)
        #expect(commentator.next(at: 0, duringRally: false) == nil)
    }

    @Test func aForfeitIsCalled() {
        var commentator = Commentator(names: names)
        commentator.observe([.gameOver(winner: .playerB)], at: 0)

        #expect(commentator.next(at: 0, duringRally: false)?.text == "Game, Computer, by forfeit.")
    }

    @Test func callsWaitWhileARallyIsOn() {
        var commentator = Commentator(names: names)
        commentator.observe([.pointScored(winner: .playerA, score: Score(a: 1, b: 0))], at: 0)

        #expect(commentator.next(at: 500_000, duringRally: true) == nil)
        #expect(commentator.next(at: 600_000, duringRally: false)?.kind == .call)
    }

    @Test func linesOlderThanThreeSecondsAreDropped() {
        var commentator = Commentator(names: names)
        commentator.observe([.pointScored(winner: .playerA, score: Score(a: 1, b: 0))], at: 1_000_000)
        commentator.observe([.pointScored(winner: .playerA, score: Score(a: 2, b: 0))], at: 3_500_000)

        #expect(commentator.next(at: 4_000_001, duringRally: false)?.text == "Love, two.")
        #expect(commentator.next(at: 4_000_001, duringRally: false) == nil)
    }

    @Test func everyLineTheRefereeCanSayHasARecording() {
        let recorded = Set(Umpire.everyLine(names: ["Player A", "Player B", "Computer"], target: 11))
        var random = SplitMix64(seed: 3)
        var said: Set<String> = []
        for _ in 0..<120 {
            var game = GameState(seed: random.next())
            var commentator = Commentator(names: names)
            while true {
                var input = StepInput(targetA: Double.random(in: 0...1, using: &random), targetB: Double.random(in: 0...1, using: &random))
                if Int.random(in: 0..<30, using: &random) == 0 {
                    input.swings = [Swing(side: Bool.random(using: &random) ? .playerA : .playerB, step: game.step, strength: Double.random(in: 0...1, using: &random), aim: 0)]
                }
                commentator.observe(game.step(input), at: 0)
                while let line = commentator.next(at: 0, duringRally: false) {
                    said.insert(line.text)
                }
                if case .gameOver = game.phase { break }
            }
        }

        #expect(said.subtracting(recorded).isEmpty, "Not recorded: \(said.subtracting(recorded).sorted())")
        #expect(said.count > 40)
    }

    @Test func everyRecordingHasItsOwnFileName() {
        let lines = Umpire.everyLine(names: ["Player A", "Player B", "Computer"], target: 11) + OpponentLine.allCases.flatMap(\.lines)

        #expect(Set(lines.map(VoiceClip.name)).count == lines.count)
    }
}

struct OpponentLineTests {
    private let names: [Side: String] = [.playerA: "Player A", .playerB: "Computer"]

    @Test(arguments: [
        ([GameEvent.hit(.playerB, strength: 0.9, rally: 2), .pointScored(winner: .playerB, score: Score(a: 1, b: 2))], OpponentLine.smashWinner),
        ([.whiff(.playerA), .pointScored(winner: .playerB, score: Score(a: 1, b: 2))], .theyWhiffed),
        ([.whiff(.playerB), .pointScored(winner: .playerA, score: Score(a: 2, b: 1))], .whiffed),
        ([.hit(.playerA, strength: 0.9, rally: 2), .pointScored(winner: .playerA, score: Score(a: 2, b: 1))], .beatenBySmash),
        ([.hit(.playerA, strength: 0.5, rally: 2), .edgeHit(.playerA), .pointScored(winner: .playerA, score: Score(a: 2, b: 1))], .beatenByEdge),
        ([.hit(.playerB, strength: 0.5, rally: 9), .pointScored(winner: .playerB, score: Score(a: 1, b: 2))], .wonALongRally),
        ([.hit(.playerA, strength: 0.5, rally: 9), .pointScored(winner: .playerA, score: Score(a: 2, b: 1))], .lostALongRally),
        ([.pointScored(winner: .playerB, score: Score(a: 4, b: 10))], .hasMatchPoint),
        ([.pointScored(winner: .playerA, score: Score(a: 10, b: 4))], .facesMatchPoint),
        ([.pointScored(winner: .playerB, score: Score(a: 4, b: 11)), .gameOver(winner: .playerB)], .wonTheGame),
        ([.pointScored(winner: .playerA, score: Score(a: 11, b: 4)), .gameOver(winner: .playerA)], .lostTheGame),
    ])
    func theComputerReactsToWhatJustHappened(events: [GameEvent], reaction: OpponentLine) {
        var commentator = Commentator(names: names, opponent: .playerB, seed: 1)
        commentator.observe(events, at: 0)

        let lines = drain(&commentator)
        #expect(lines.filter { $0.kind == .opponent }.map(\.text).allSatisfy(reaction.lines.contains))
        #expect(lines.filter { $0.kind == .opponent }.count == 1)
    }

    @Test func theComputerSpeaksBeforeTheReferee() {
        var commentator = Commentator(names: names, opponent: .playerB, seed: 1)
        commentator.observe([.hit(.playerB, strength: 0.9, rally: 2), .pointScored(winner: .playerB, score: Score(a: 1, b: 2))], at: 0)

        #expect(drain(&commentator).map(\.kind) == [.opponent, .call, .highlight])
    }

    @Test func theComputerCanStillTalkOnceTheNextRallyStarts() {
        var commentator = Commentator(names: names, opponent: .playerB, seed: 1)
        commentator.observe([.whiff(.playerA), .pointScored(winner: .playerB, score: Score(a: 1, b: 2))], at: 0)

        #expect(commentator.next(at: 0, duringRally: true)?.kind == .opponent)
        #expect(commentator.next(at: 0, duringRally: true) == nil)
        #expect(commentator.next(at: 0, duringRally: false)?.kind == .call)
    }

    @Test func mostPlainPointsGetAReaction() {
        var commentator = Commentator(names: names, opponent: .playerB, seed: 7)
        var reactions = 0
        for point in 1...100 {
            commentator.observe([.hit(.playerA, strength: 0.5, rally: 2), .pointScored(winner: .playerA, score: Score(a: point % 3, b: 0))], at: 0)
            reactions += drain(&commentator).filter { $0.kind == .opponent }.count
        }

        #expect((65...95).contains(reactions))
    }

    @Test func theSameLineIsNeverSaidTwiceInARow() {
        var commentator = Commentator(names: names, opponent: .playerB, seed: 3)
        var said: [String] = []
        for _ in 1...20 {
            commentator.observe([.whiff(.playerA), .pointScored(winner: .playerB, score: Score(a: 0, b: 1))], at: 0)
            said += drain(&commentator).filter { $0.kind == .opponent }.map(\.text)
        }

        #expect(zip(said, said.dropFirst()).allSatisfy { $0 != $1 })
        #expect(Set(said).count > 1)
    }

    @Test func withoutAComputerNobodyReacts() {
        var commentator = Commentator(names: names)
        commentator.observe([.whiff(.playerA), .pointScored(winner: .playerB, score: Score(a: 1, b: 2))], at: 0)

        #expect(!drain(&commentator).contains { $0.kind == .opponent })
    }

    private func drain(_ commentator: inout Commentator) -> [CommentaryLine] {
        var lines: [CommentaryLine] = []
        while let line = commentator.next(at: 0, duringRally: false) {
            lines.append(line)
        }
        return lines
    }
}
