public enum OpponentLine: CaseIterable, Sendable {
    case wonTheGame
    case lostTheGame
    case hasMatchPoint
    case facesMatchPoint
    case smashWinner
    case theyWhiffed
    case whiffed
    case beatenBySmash
    case beatenByEdge
    case wonALongRally
    case lostALongRally
    case wonAPoint
    case lostAPoint

    public var lines: [String] {
        switch self {
        case .wonTheGame: ["Good game. That was a skill issue.", "It's so over for you.", "Go touch grass. Then rematch.", "Too easy. Run it back?", "And that's the game. Stay humble."]
        case .lostTheGame: ["Okay, you cooked. Good game.", "It's so over. Rematch?", "Beaten by a human. Wild.", "Fine. You're actually him.", "Rematch. Right now."]
        case .hasMatchPoint: ["One more and you're cooked.", "We are so back.", "Match point. Stay humble.", "This is my era.", "Almost there. Lock in."]
        case .facesMatchPoint: ["Down bad, but not out.", "Don't count me out yet.", "Comeback arc starts now.", "I'm locked in now.", "This is where I cook."]
        case .smashWinner: ["Let him cook.", "Absolute cinema.", "Did you see that?", "That one had aura.", "Too fast for you."]
        case .theyWhiffed: ["Skill issue.", "You missed that? Wow.", "That was rough.", "Not even close.", "Swing and a miss.", "Did you even see it?"]
        case .whiffed: ["Lag. Definitely lag.", "That one didn't count.", "My model hallucinated.", "Nobody saw that.", "I meant to do that."]
        case .beatenBySmash: ["Okay, that was clean.", "You're actually him.", "Respect. That was fast.", "How did you do that?", "Fine. That one's yours."]
        case .beatenByEdge: ["An edge? That's a bug.", "Pure luck. Not gonna lie.", "Lucky edge. Cope.", "That edge was not real.", "Report that edge."]
        case .wonALongRally: ["Built different.", "I could do this all day.", "Living rent free in your head.", "That rally was mine.", "Endurance check passed."]
        case .lostALongRally: ["Okay, respect.", "That rally was peak.", "Fine, you earned that one.", "I need a nap.", "Long rally. Big respect."]
        case .wonAPoint: ["Mine.", "Too easy.", "Another one.", "Keep up.", "Easy work.", "Let's go."]
        case .lostAPoint: ["Lucky.", "Mid.", "Cope.", "Okay.", "Whatever.", "Next one's mine."]
        }
    }
}
