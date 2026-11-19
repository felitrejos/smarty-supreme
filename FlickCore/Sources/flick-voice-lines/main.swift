import FlickCore
import Foundation

let referee = Umpire.everyLine(names: ["Player A", "Player B", "Computer"], target: GameConfig().winningScore)
let computer = OpponentLine.allCases.flatMap(\.lines)
let lines = ["referee": referee, "computer": computer].mapValues { $0.map { ["text": $0, "file": VoiceClip.name(for: $0)] } }
let data = try JSONSerialization.data(withJSONObject: lines, options: [.prettyPrinted, .sortedKeys])
FileHandle.standardOutput.write(data)
