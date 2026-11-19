import AVFoundation
import SmartyCore
import OSLog

@MainActor
final class Announcer {
    enum Speaker: String {
        case referee
        case computer
    }

    private static let reverbMix: Float = 30
    private static let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
    private static let log = Logger(subsystem: "com.smartysupreme.host", category: "Announcer")

    private let engine = AVAudioEngine()
    private let voice = AVAudioPlayerNode()
    private let hall = AVAudioUnitReverb()
    private var clips: [String: AVAudioPCMBuffer] = [:]
    private(set) var isSpeaking = false

    init() {
        hall.loadFactoryPreset(.largeHall)
        hall.wetDryMix = Self.reverbMix
        engine.attach(voice)
        engine.attach(hall)
        engine.connect(voice, to: hall, format: Self.format)
        engine.connect(hall, to: engine.mainMixerNode, format: Self.format)
    }

    func say(_ line: String, as speaker: Speaker) {
        do {
            let clip = try clip(VoiceClip.name(for: line), speaker: speaker)
            if !engine.isRunning {
                try engine.start()
            }
            isSpeaking = true
            voice.scheduleBuffer(clip, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor in self?.isSpeaking = false }
            }
            voice.play()
        } catch {
            Self.log.error("Couldn’t say \(line, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func clip(_ name: String, speaker: Speaker) throws -> AVAudioPCMBuffer {
        let key = "\(speaker.rawValue)/\(name)"
        if let clip = clips[key] {
            return clip
        }
        guard let url = Bundle.main.url(forResource: name, withExtension: "m4a", subdirectory: "Voice/\(speaker.rawValue)") else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: key])
        }
        let file = try AVAudioFile(forReading: url)
        let source = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: source)
        let converter = AVAudioConverter(from: file.processingFormat, to: Self.format)!
        let ratio = Self.format.sampleRate / file.processingFormat.sampleRate
        let clip = AVAudioPCMBuffer(pcmFormat: Self.format, frameCapacity: AVAudioFrameCount(Double(source.frameLength) * ratio) + 1024)!
        var supplied = false
        var failure: NSError?
        converter.convert(to: clip, error: &failure) { _, status in
            if supplied {
                status.pointee = .endOfStream
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return source
        }
        if let failure {
            throw failure
        }
        clips[key] = clip
        return clip
    }
}
