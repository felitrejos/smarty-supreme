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
        case .wonTheGame: ["Good game. Skill issue, honestly.", "It's so over for you.", "Touch grass, then we run it back."]
        case .lostTheGame: ["Okay, you cooked. Good game.", "It's so over. Rematch?", "Ratioed by a human. Wild."]
        case .hasMatchPoint: ["One more and you're cooked.", "We are so back.", "Match point. Stay humble."]
        case .facesMatchPoint: ["Down bad, but not out.", "Don't count me out yet.", "Comeback arc starts now."]
        case .smashWinner: ["Let him cook.", "Absolute cinema.", "That's a ten x shot."]
        case .theyWhiffed: ["Skill issue.", "Big swing, zero contact.", "Air ball, no cap."]
        case .whiffed: ["Lag. Definitely lag.", "That one didn't count.", "My model hallucinated."]
        case .beatenBySmash: ["Okay, that was clean.", "You're actually him.", "Fine, that's a W."]
        case .beatenByEdge: ["An edge? That's a bug, not a feature.", "Pure luck, not gonna lie.", "Lucky edge. Cope."]
        case .wonALongRally: ["Built different.", "I could do this all day.", "Living rent free in your head."]
        case .lostALongRally: ["Okay, respect.", "That rally was peak.", "Fine, you earned that one."]
        case .wonAPoint: ["Mine.", "Too easy.", "Another W."]
        case .lostAPoint: ["Lucky.", "Mid.", "Cope."]
        }
    }
}
