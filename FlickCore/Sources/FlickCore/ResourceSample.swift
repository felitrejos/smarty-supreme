import Darwin
import Foundation

public struct ResourceSample: Sendable {
    public let cpuSeconds: Double
    public let wallSeconds: Double
    public let memoryBytes: UInt64

    public init(cpuSeconds: Double, wallSeconds: Double, memoryBytes: UInt64) {
        self.cpuSeconds = cpuSeconds
        self.wallSeconds = wallSeconds
        self.memoryBytes = memoryBytes
    }

    public static func current() -> ResourceSample {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let cpu = seconds(usage.ru_utime) + seconds(usage.ru_stime)
        return ResourceSample(cpuSeconds: cpu, wallSeconds: ProcessInfo.processInfo.systemUptime, memoryBytes: footprint())
    }

    public func cpuShare(since earlier: ResourceSample) -> Double {
        (cpuSeconds - earlier.cpuSeconds) / (wallSeconds - earlier.wallSeconds)
    }

    private static func seconds(_ time: timeval) -> Double {
        Double(time.tv_sec) + Double(time.tv_usec) / 1_000_000
    }

    private static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        precondition(result == KERN_SUCCESS, "Reading this process's own memory cannot fail")
        return info.phys_footprint
    }
}
