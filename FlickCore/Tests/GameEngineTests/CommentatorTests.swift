import FlickCore
import Testing

struct CommentatorTests {
    private let names: [Side: String] = [.playerA: "Player A", .playerB: "Computer"]

    @Test func aPointIsCalledWithTheWinnerAndTheScore() {
        var commentator = Commentator(names: names)
        commentator.observe([.pointScored(winner: .playerA, score: Score(a: 7, b: 5))], target: 11, at: 0)

        #expect(commentator.next(at: 0, duringRally: false)?.text == "Point to Player A. Player A leads 7 to 5.")
    }

    @Test func aTiedScoreIsCalledAsAll() {
        var commentator = Commentator(names: names)
        commentator.observe([.pointScored(winner: .playerB, score: Score(a: 4, b: 4))], target: 11, at: 0)

        #expect(commentator.next(at: 0, duringRally: false)?.text == "Point to Computer. 4 all.")
    }

    @Test func aWhiffThatLosesThePointIsMentioned() {
        var commentator = Commentator(names: names)
        commentator.observe([.whiff(.playerB)], target: 11, at: 0)
        commentator.observe([.pointScored(winner: .playerA, score: Score(a: 1, b: 0))], target: 11, at: 0)

        #expect(commentator.next(at: 0, duringRally: false)?.text == "Computer whiffs. Point to Player A. Player A leads 1 to 0.")
    }

    @Test func anEdgeWinnerIsMentioned() {
        var commentator = Commentator(names: names)
        commentator.observe([.hit(.playerA, strength: 0.5, rally: 1), .edgeHit(.playerA)], target: 11, at: 0)
        commentator.observe([.pointScored(winner: .playerA, score: Score(a: 1, b: 0))], target: 11, at: 0)

        #expect(commentator.next(at: 0, duringRally: false)?.text == "Off the edge from Player A. Point to Player A. Player A leads 1 to 0.")
    }

    @Test func aSmashWinnerIsAHighlightSpokenAfterTheCall() {
        var commentator = Commentator(names: names)
        commentator.observe([.hit(.playerA, strength: 0.9, rally: 3)], target: 11, at: 0)
        commentator.observe([.pointScored(winner: .playerA, score: Score(a: 2, b: 1))], target: 11, at: 0)

        #expect(commentator.next(at: 0, duringRally: false)?.kind == .call)
        #expect(commentator.next(at: 0, duringRally: false) == CommentaryLine(text: "Smash winner from Player A!", kind: .highlight, createdAt: 0))
        #expect(commentator.next(at: 0, duringRally: false) == nil)
    }

    @Test func theScoreIsCalledEvenIfTheNextRallyStartsBeforeTheHighlight() {
        var commentator = Commentator(names: names)
        commentator.observe([.pointScored(winner: .playerA, score: Score(a: 10, b: 10))], target: 11, at: 0)

        #expect(commentator.next(at: 0, duringRally: false)?.text == "Point to Player A. 10 all.")
        #expect(commentator.next(at: 500_000, duringRally: true)?.text == "Deuce!")
    }

    @Test func aForfeitIsCalled() {
        var commentator = Commentator(names: names)
        commentator.observe([.gameOver(winner: .playerB)], target: 11, at: 0)

        #expect(commentator.next(at: 0, duringRally: false)?.text == "Game to Computer by forfeit.")
    }

    @Test func aSmashThatComesBackIsNotAWinner() {
        var commentator = Commentator(names: names)
        commentator.observe([.hit(.playerA, strength: 0.9, rally: 3)], target: 11, at: 0)
        commentator.observe([.hit(.playerB, strength: 0.4, rally: 4)], target: 11, at: 0)
        commentator.observe([.pointScored(winner: .playerB, score: Score(a: 1, b: 2))], target: 11, at: 0)

        #expect(commentator.next(at: 0, duringRally: false)?.kind == .call)
        #expect(commentator.next(at: 0, duringRally: false) == nil)
    }

    @Test func aRallyOfTenIsAHighlightSpokenDuringTheRally() {
        var commentator = Commentator(names: names)
        for rally in 1...12 {
            commentator.observe([.hit(rally.isMultiple(of: 2) ? .playerB : .playerA, strength: 0.5, rally: rally)], target: 11, at: 0)
        }

        #expect(commentator.next(at: 0, duringRally: true)?.text == "Rally of 10!")
        #expect(commentator.next(at: 0, duringRally: true) == nil)
    }

    @Test func eachPointGetsAtMostOneCallAndOneHighlight() {
        var commentator = Commentator(names: names)
        for rally in 1...10 {
            commentator.observe([.hit(rally.isMultiple(of: 2) ? .playerB : .playerA, strength: 0.9, rally: rally)], target: 11, at: 0)
        }
        commentator.observe([.pointScored(winner: .playerB, score: Score(a: 10, b: 10))], target: 11, at: 0)

        let lines = [commentator.next(at: 0, duringRally: false), commentator.next(at: 0, duringRally: false), commentator.next(at: 0, duringRally: false)]
        #expect(lines.compactMap(\.?.kind) == [.highlight, .call])
        #expect(lines[0]?.text == "Rally of 10!")
    }

    @Test(arguments: [
        (Score(a: 10, b: 10), "Deuce!"),
        (Score(a: 10, b: 9), "Match point, Player A."),
        (Score(a: 11, b: 12), "Match point, Computer."),
    ])
    func deuceAndMatchPointAreHighlights(score: Score, highlight: String) {
        var commentator = Commentator(names: names)
        commentator.observe([.pointScored(winner: score.a > score.b ? .playerA : .playerB, score: score)], target: 11, at: 0)
        _ = commentator.next(at: 0, duringRally: false)

        #expect(commentator.next(at: 0, duringRally: false)?.text == highlight)
    }

    @Test func theGameEndIsOneCallWithTheFinalScore() {
        var commentator = Commentator(names: names)
        commentator.observe([.pointScored(winner: .playerB, score: Score(a: 6, b: 11)), .gameOver(winner: .playerB)], target: 11, at: 0)

        #expect(commentator.next(at: 0, duringRally: false)?.text == "Game to Computer, 11 to 6!")
        #expect(commentator.next(at: 0, duringRally: false) == nil)
    }

    @Test func callsWaitWhileARallyIsOn() {
        var commentator = Commentator(names: names)
        commentator.observe([.pointScored(winner: .playerA, score: Score(a: 1, b: 0))], target: 11, at: 0)

        #expect(commentator.next(at: 500_000, duringRally: true) == nil)
        #expect(commentator.next(at: 600_000, duringRally: false)?.kind == .call)
    }

    @Test func linesOlderThanThreeSecondsAreDropped() {
        var commentator = Commentator(names: names)
        commentator.observe([.pointScored(winner: .playerA, score: Score(a: 1, b: 0))], target: 11, at: 1_000_000)
        commentator.observe([.pointScored(winner: .playerA, score: Score(a: 2, b: 0))], target: 11, at: 3_500_000)

        #expect(commentator.next(at: 4_000_001, duringRally: false)?.text == "Point to Player A. Player A leads 2 to 0.")
        #expect(commentator.next(at: 4_000_001, duringRally: false) == nil)
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
        commentator.observe(events, target: 11, at: 0)

        let lines = drain(&commentator)
        #expect(lines.filter { $0.kind == .opponent }.map(\.text).allSatisfy(reaction.lines.contains))
        #expect(lines.filter { $0.kind == .opponent }.count == 1)
    }

    @Test func theComputerSpeaksAfterTheReferee() {
        var commentator = Commentator(names: names, opponent: .playerB, seed: 1)
        commentator.observe([.hit(.playerB, strength: 0.9, rally: 2), .pointScored(winner: .playerB, score: Score(a: 1, b: 2))], target: 11, at: 0)

        #expect(drain(&commentator).map(\.kind) == [.call, .highlight, .opponent])
    }

    @Test func theComputerWaitsForTheRallyToEnd() {
        var commentator = Commentator(names: names, opponent: .playerB, seed: 1)
        commentator.observe([.whiff(.playerA), .pointScored(winner: .playerB, score: Score(a: 1, b: 2))], target: 11, at: 0)
        _ = commentator.next(at: 0, duringRally: false)

        #expect(commentator.next(at: 0, duringRally: true) == nil)
        #expect(commentator.next(at: 0, duringRally: false)?.kind == .opponent)
    }

    @Test func plainPointsGetAReactionOnlySometimes() {
        var commentator = Commentator(names: names, opponent: .playerB, seed: 7)
        var reactions = 0
        for point in 1...100 {
            commentator.observe([.hit(.playerA, strength: 0.5, rally: 2), .pointScored(winner: .playerA, score: Score(a: point % 3, b: 0))], target: 11, at: 0)
            reactions += drain(&commentator).filter { $0.kind == .opponent }.count
        }

        #expect((10...40).contains(reactions))
    }

    @Test func theSameLineIsNeverSaidTwiceInARow() {
        var commentator = Commentator(names: names, opponent: .playerB, seed: 3)
        var said: [String] = []
        for _ in 1...20 {
            commentator.observe([.whiff(.playerA), .pointScored(winner: .playerB, score: Score(a: 0, b: 1))], target: 11, at: 0)
            said += drain(&commentator).filter { $0.kind == .opponent }.map(\.text)
        }

        #expect(zip(said, said.dropFirst()).allSatisfy { $0 != $1 })
        #expect(Set(said).count > 1)
    }

    @Test func withoutAComputerNobodyReacts() {
        var commentator = Commentator(names: names)
        commentator.observe([.whiff(.playerA), .pointScored(winner: .playerB, score: Score(a: 1, b: 2))], target: 11, at: 0)

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
