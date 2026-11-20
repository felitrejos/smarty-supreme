import AVFoundation

@MainActor
final class SoundBoard {
    enum Cue {
        case paddle(strength: Double, isClean: Bool)
        case table
        case net
        case point
        case win
    }

    private static let voices = 8
    private static let reverbMix: Float = 24
    private static let crowdVolume: Float = 0.22
    private static let paddleCount = 6
    private static let tableCount = 8
    private static let cleanPitch: Float = 1.05
    private static let cleanPitchPerStrength: Float = 0.08
    private static let edgePitch: Float = 0.82
    private static let edgeVolume: Float = 0.7

    private let engine = AVAudioEngine()
    private let hits = AVAudioMixerNode()
    private let reverb = AVAudioUnitReverb()
    private let crowd = AVAudioPlayerNode()
    private let players: [AVAudioPlayerNode]
    private let pitches: [AVAudioUnitVarispeed]
    private let paddles: [AVAudioPCMBuffer]
    private let tables: [AVAudioPCMBuffer]
    private let applause: AVAudioPCMBuffer
    private let cheer: AVAudioPCMBuffer
    private var nextVoice = 0

    init() throws {
        paddles = try (1...Self.paddleCount).map { try Self.buffer("paddle-\($0)") }
        tables = try (1...Self.tableCount).map { try Self.buffer("table-\($0)") }
        applause = try Self.buffer("applause")
        cheer = try Self.buffer("cheer")
        let murmur = try Self.buffer("crowd-murmur")
        players = (0..<Self.voices).map { _ in AVAudioPlayerNode() }
        pitches = (0..<Self.voices).map { _ in AVAudioUnitVarispeed() }

        reverb.loadFactoryPreset(.largeHall)
        reverb.wetDryMix = Self.reverbMix
        engine.attach(hits)
        engine.attach(reverb)
        engine.attach(crowd)
        engine.connect(hits, to: reverb, format: nil)
        engine.connect(reverb, to: engine.mainMixerNode, format: nil)
        engine.connect(crowd, to: engine.mainMixerNode, format: murmur.format)
        for (player, pitch) in zip(players, pitches) {
            engine.attach(player)
            engine.attach(pitch)
            engine.connect(player, to: pitch, format: murmur.format)
            engine.connect(pitch, to: hits, fromBus: 0, toBus: hits.nextAvailableInputBus, format: murmur.format)
        }
        try engine.start()
        crowd.volume = Self.crowdVolume
        crowd.scheduleBuffer(murmur, at: nil, options: .loops)
        crowd.play()
    }

    func play(_ cue: Cue, pan: Float) {
        let player = players[nextVoice]
        pitches[nextVoice].rate = rate(for: cue)
        nextVoice = (nextVoice + 1) % players.count
        let (buffer, volume) = sound(for: cue)
        player.pan = pan
        player.volume = volume
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        player.play()
    }

    // A clean hit rings a little higher and brighter the harder it is struck; an edge is a duller, lower knock.
    private func rate(for cue: Cue) -> Float {
        guard case .paddle(let strength, let isClean) = cue else { return 1 }
        return isClean ? Self.cleanPitch + Self.cleanPitchPerStrength * Float(strength) : Self.edgePitch
    }

    private func sound(for cue: Cue) -> (AVAudioPCMBuffer, Float) {
        switch cue {
        case .paddle(let strength, let isClean): (paddles[Int.random(in: paddles.indices)], Float(0.35 + 0.65 * strength) * (isClean ? 1 : Self.edgeVolume))
        case .table: (tables[Int.random(in: tables.indices)], 0.55)
        case .net: (tables[Int.random(in: tables.indices)], 0.18)
        case .point: (applause, 0.45)
        case .win: (cheer, 0.6)
        }
    }

    private static func buffer(_ name: String) throws -> AVAudioPCMBuffer {
        let url = Bundle.main.url(forResource: name, withExtension: "wav")!
        let file = try AVAudioFile(forReading: url)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        return buffer
    }
}
