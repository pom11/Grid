import Foundation
import Darwin.Mach
import os.log

@MainActor
class CPUReader: ObservableObject {
    @Published var usage: Double = 0.0

    private let logger = Logger(subsystem: "ro.pom.grid", category: "cpu")
    private let hostPort = mach_host_self()
    private var lastCPUInfo: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?

    func read() {
        var numCPUs: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCPUInfo: mach_msg_type_number_t = 0
        var numCPUsU: UInt32 = 0

        let result = host_processor_info(
            hostPort,
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUsU,
            &cpuInfo,
            &numCPUInfo
        )

        guard result == KERN_SUCCESS, let cpuInfo = cpuInfo else {
            logger.error("Failed to get CPU info: \(result)")
            return
        }

        numCPUs = natural_t(numCPUsU)

        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: cpuInfo),
                vm_size_t(Int(numCPUInfo) * MemoryLayout<integer_t>.stride)
            )
        }

        var totalUser: UInt64 = 0
        var totalSystem: UInt64 = 0
        var totalIdle: UInt64 = 0
        var totalNice: UInt64 = 0

        for i in 0..<Int(numCPUs) {
            let offset = Int(CPU_STATE_MAX) * i
            totalUser += UInt64(cpuInfo[offset + Int(CPU_STATE_USER)])
            totalSystem += UInt64(cpuInfo[offset + Int(CPU_STATE_SYSTEM)])
            totalIdle += UInt64(cpuInfo[offset + Int(CPU_STATE_IDLE)])
            totalNice += UInt64(cpuInfo[offset + Int(CPU_STATE_NICE)])
        }

        if let last = lastCPUInfo {
            let userDelta = totalUser - last.user
            let systemDelta = totalSystem - last.system
            let idleDelta = totalIdle - last.idle
            let niceDelta = totalNice - last.nice

            let totalDelta = userDelta + systemDelta + idleDelta + niceDelta

            if totalDelta > 0 {
                let activeDelta = userDelta + systemDelta + niceDelta
                usage = Double(activeDelta) / Double(totalDelta)
            }
        }

        lastCPUInfo = (user: totalUser, system: totalSystem, idle: totalIdle, nice: totalNice)
    }
}
