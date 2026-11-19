import FlickCore
import Foundation
import UIKit

@MainActor
final class PaddleController {
    private static let pointerInterval = DispatchTimeInterval.microseconds(16_667)
    private static let byeDelivery = DispatchTimeInterval.milliseconds(300)
    private static let longestName = 40
    private static let touchStartPosition = 0.5

    let sensing = PaddleSensing()
    let link: PaddleLink
    let launchedAt: Microseconds
    let networkFailure = NetworkFailure()
    let haptics = HapticPlayer()
    let stats = DeviceStats()

    private let motion: MotionService
    private let transport: MultipeerTransport
    private let pointerQueue = DispatchQueue(label: "pointer", qos: .userInteractive)
    private var pointerTimer: DispatchSourceTimer?
    private var pendingDisconnect: DispatchWorkItem?
    private var isHalted = false

    init(motion: MotionService, launchedAt: Microseconds) {
        let relay = EventRelay()
        transport = MultipeerTransport(mode: .browse, onEvent: relay.forward, onFailure: networkFailure.record)
        link = PaddleLink(
            name: String(UIDevice.current.name.prefix(Self.longestName)),
            transport: transport,
            clock: SystemClock(),
            onHaptic: { [haptics, sensing] kind in
                let swingStrength = sensing.snapshot.lastSwing?.strength
                Task { @MainActor in haptics.play(kind, swingStrength: swingStrength) }
            }
        )
        relay.connect(link.handle)
        self.motion = motion
        self.launchedAt = launchedAt
    }

    func start() {
        guard pointerTimer == nil, !isHalted else { return }
        if let pendingDisconnect {
            pendingDisconnect.cancel()
            self.pendingDisconnect = nil
            transport.stop()
        }
        transport.start()
        if motion.isAvailable {
            motion.start(onSample: forwardSample, onError: sensing.reportSensorError)
        } else {
            sensing.setTouchPosition(Self.touchStartPosition)
            link.announceCalibration(sensing.snapshot.sensitivity)
        }
        pointerTimer = makePointerTimer()
        haptics.prepare()
        stats.start()
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func stop(_ reason: ByeReason) {
        guard pauseSensing() else { return }
        link.leave(reason)
        let disconnect = DispatchWorkItem { [transport] in transport.stop() }
        pendingDisconnect = disconnect
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.byeDelivery, execute: disconnect)
    }

    func swipeSwing() {
        let swing = TouchInput.swing(at: SystemClock().now)
        sensing.recordTouchSwing(swing)
        link.sendSwing(swing)
    }

    func dragPaddle(to x: Double, across width: Double) {
        sensing.setTouchPosition(TouchInput.position(x: x, width: width))
    }

    func setSensitivity(_ sensitivity: Sensitivity) {
        if sensing.setSensitivity(sensitivity) {
            link.announceCalibration(sensitivity)
        }
    }

    private func haltForVersionMismatch() {
        isHalted = true
        guard pauseSensing() else { return }
        transport.stop()
    }

    private func pauseSensing() -> Bool {
        guard let pointerTimer else { return false }
        pointerTimer.cancel()
        self.pointerTimer = nil
        motion.stop()
        UIApplication.shared.isIdleTimerDisabled = false
        return true
    }

    private var forwardSample: @Sendable (MotionSample) -> Void {
        { [sensing, link] sample in
            let outcome = sensing.process(sample)
            if let swing = outcome.swing {
                link.sendSwing(swing)
            }
            if let sensitivity = outcome.calibratedWith {
                link.announceCalibration(sensitivity)
            }
        }
    }

    private func makePointerTimer() -> DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(queue: pointerQueue)
        timer.schedule(deadline: .now(), repeating: Self.pointerInterval, leeway: .microseconds(500))
        timer.setEventHandler { @Sendable [weak self, sensing, link] in
            if link.status == .refused(.versionMismatch) {
                Task { @MainActor in self?.haltForVersionMismatch() }
                return
            }
            if let position = sensing.position {
                link.sendPointer(position)
            }
        }
        timer.resume()
        return timer
    }
}
