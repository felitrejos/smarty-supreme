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
        case .wonTheGame: ["Good game. Better luck next time.", "And that’s the match. Rematch?", "Too easy. Just kidding, well played."]
        case .lostTheGame: ["Well played. I want a rematch.", "You got me. Good game.", "Fine, you win this one."]
        case .hasMatchPoint: ["One more point and it’s mine.", "Match point. No pressure.", "Almost there."]
        case .facesMatchPoint: ["It’s not over yet.", "I can still come back.", "Don’t celebrate yet."]
        case .smashWinner: ["Too fast for you?", "Did you see that one?", "Boom."]
        case .theyWhiffed: ["Missed me!", "Swing and a miss.", "Close, but no."]
        case .whiffed: ["I’ll get the next one.", "Nobody saw that.", "My paddle slipped."]
        case .beatenBySmash: ["Ouch. Nice shot.", "How am I supposed to return that?", "Okay, that one was fast."]
        case .beatenByEdge: ["Off the edge? Lucky.", "That edge was pure luck.", "Really? The edge?"]
        case .wonALongRally: ["What a rally. Mine, though.", "I could do this all day.", "You almost had me."]
        case .lostALongRally: ["Okay, that was a good rally.", "Fine, you earned that one.", "I’m getting tired."]
        case .wonAPoint: ["Mine.", "Point to me.", "Keep up!"]
        case .lostAPoint: ["Nice one.", "Lucky.", "Hmm."]
        }
    }
}
