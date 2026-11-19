import FlickCore
import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class DeviceStats {
    static let cpuBudget = 0.15
    static let batteryBudgetPerHalfHour: Float = 0.08
    private static let interval: TimeInterval = 2
    private static let batteryStep: Float = 0.05

    private struct BatteryBaseline {
        let level: Float
        let since: TimeInterval
    }

    private(set) var cpuShare: Double?
    private(set) var batteryDrop: Float?
    private(set) var batteryMinutes = 0.0

    @ObservationIgnored private var lastSample: ResourceSample?
    @ObservationIgnored private var baseline: BatteryBaseline?
    @ObservationIgnored private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        UIDevice.current.isBatteryMonitoringEnabled = true
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
    }

    func isWithinBudget(cpu: Double) -> Bool {
        guard cpu <= Self.cpuBudget else { return false }
        guard let batteryDrop, batteryDrop >= Self.batteryStep else { return true }
        return batteryDrop / Float(batteryMinutes) * 30 <= Self.batteryBudgetPerHalfHour
    }

    private func sample() {
        let sample = ResourceSample.current()
        if let lastSample {
            cpuShare = sample.cpuShare(since: lastSample)
        }
        lastSample = sample
        sampleBattery(at: sample.wallSeconds)
    }

    private func sampleBattery(at now: TimeInterval) {
        let device = UIDevice.current
        guard device.batteryState == .unplugged, device.batteryLevel >= 0 else {
            baseline = nil
            batteryDrop = nil
            return
        }
        let start = baseline ?? BatteryBaseline(level: device.batteryLevel, since: now)
        baseline = start
        batteryDrop = start.level - device.batteryLevel
        batteryMinutes = (now - start.since) / 60
    }
}
