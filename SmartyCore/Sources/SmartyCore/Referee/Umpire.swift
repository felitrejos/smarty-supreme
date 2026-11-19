public enum Umpire {
    public static let longRally = "What a rally!"

    private static let words = ["love", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
                                "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty", "twenty one"]

    public static func call(_ score: Score, server: Side, target: Int, name: (Side) -> String) -> String {
        if score.a == score.b {
            return score.a >= target - 1 ? "Deuce." : "\(word(score.a).capitalizedFirst) all."
        }
        let leader: Side = score.a > score.b ? .playerA : .playerB
        if score[leader.opponent] >= target - 1 {
            return "Advantage, \(name(leader))."
        }
        return "\(word(score[server]).capitalizedFirst), \(word(score[server.opponent]))."
    }

    public static func game(_ winner: String, score: Score, target: Int) -> String {
        let (high, low) = (max(score.a, score.b), min(score.a, score.b))
        return high == target ? "Game, \(winner). \(word(high).capitalizedFirst), \(word(low))." : "Game, \(winner)."
    }

    public static func forfeit(_ winner: String) -> String {
        "Game, \(winner), by forfeit."
    }

    public static func smash(_ winner: String) -> String {
        "Smash winner, \(winner)!"
    }

    public static func matchPoint(_ leader: String) -> String {
        "Match point, \(leader)."
    }

    public static func everyLine(names: [String], target: Int) -> [String] {
        var lines: Set<String> = [longRally]
        for first in 0..<target {
            for second in 0..<target where first + second > 0 {
                lines.insert(call(Score(a: first, b: second), server: .playerA, target: target) { _ in "" })
            }
        }
        for name in names {
            lines.insert("Advantage, \(name).")
            lines.insert(game(name, score: Score(a: target + 1, b: target - 1), target: target))
            for low in 0...(target - 2) {
                lines.insert(game(name, score: Score(a: target, b: low), target: target))
            }
            lines.insert(forfeit(name))
            lines.insert(smash(name))
            lines.insert(matchPoint(name))
        }
        return lines.sorted()
    }

    private static func word(_ number: Int) -> String {
        words.indices.contains(number) ? words[number] : "\(number)"
    }
}

public enum VoiceClip {
    public static func name(for line: String) -> String {
        let kept = line.lowercased().map { $0.isLetter || $0.isNumber ? $0 : " " }
        return String(kept).split(separator: " ").joined(separator: "-")
    }
}

extension String {
    var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}
