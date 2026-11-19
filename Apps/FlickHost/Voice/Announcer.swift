import AVFoundation

@MainActor
final class Announcer: NSObject, AVSpeechSynthesizerDelegate {
    enum Speaker {
        case referee
        case opponent
    }

    private static let opponentPitch: Float = 1.15
    private static let opponentRate: Float = 1.08

    private let synthesizer = AVSpeechSynthesizer()
    private let refereeVoice: AVSpeechSynthesisVoice?
    private let opponentVoice: AVSpeechSynthesisVoice?
    private var starts: [ObjectIdentifier: () -> Void] = [:]

    override init() {
        let voices = Self.rankedVoices()
        let referee = voices.first
        refereeVoice = referee
        opponentVoice = voices.first { $0.gender != referee?.gender } ?? voices.dropFirst().first ?? referee
        super.init()
        synthesizer.delegate = self
    }

    var isSpeaking: Bool {
        synthesizer.isSpeaking
    }

    func say(_ text: String, as speaker: Speaker, onStart: @escaping () -> Void = {}) {
        let utterance = AVSpeechUtterance(string: text)
        switch speaker {
        case .referee:
            utterance.voice = refereeVoice
        case .opponent:
            utterance.voice = opponentVoice
            utterance.pitchMultiplier = Self.opponentPitch
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * Self.opponentRate
        }
        starts[ObjectIdentifier(utterance)] = onStart
        synthesizer.speak(utterance)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in
            starts.removeValue(forKey: id)?()
        }
    }

    private static func rankedVoices() -> [AVSpeechSynthesisVoice] {
        let language = AVSpeechSynthesisVoice.currentLanguageCode()
        let prefix = String(language.prefix(2))
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(prefix) && !$0.voiceTraits.contains(.isPersonalVoice) && !$0.voiceTraits.contains(.isNoveltyVoice) }
            .sorted { rank($0, language) > rank($1, language) }
    }

    private static func rank(_ voice: AVSpeechSynthesisVoice, _ language: String) -> Int {
        voice.quality.rawValue * 2 + (voice.language == language ? 1 : 0)
    }
}
