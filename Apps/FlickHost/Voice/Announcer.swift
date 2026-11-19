import AVFoundation
import FlickCore
import OSLog

@MainActor
final class Announcer {
    enum Speaker: String {
        case referee
        case computer
    }

    private static let reverbMix: Float = 30
    private static let log = Logger(subsystem: "com.flickpong.host", category: "Announcer")

    private let engine = AVAudioEngine()
    private let voice = AVAudioPlayerNode()
    private let hall = AVAudioUnitReverb()
    private(set) var isSpeaking = false

    init() {
        hall.loadFactoryPreset(.largeHall)
        hall.wetDryMix = Self.reverbMix
        engine.attach(voice)
        engine.attach(hall)
        engine.connect(voice, to: hall, format: nil)
        engine.connect(hall, to: engine.mainMixerNode, format: nil)
    }

    func say(_ line: String, as speaker: Speaker) {
        guard let url = Bundle.main.url(forResource: VoiceClip.name(for: line), withExtension: "m4a", subdirectory: "Voice/\(speaker.rawValue)") else {
            Self.log.fault("No recording for \(line, privacy: .public)")
            return
        }
        do {
            let file = try AVAudioFile(forReading: url)
            if !engine.isRunning {
                engine.connect(voice, to: hall, format: file.processingFormat)
                try engine.start()
            }
            isSpeaking = true
            voice.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor in self?.isSpeaking = false }
            }
            voice.play()
        } catch {
            Self.log.error("Couldn’t play \(line, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
