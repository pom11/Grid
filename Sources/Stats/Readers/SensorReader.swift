import Foundation
import Combine
import os.log
import SMC

private let log = Logger(subsystem: "ro.pom.grid", category: "sensors")

final class SensorReader: ObservableObject {
    @Published var cpuTemp: Double = -1   // average celsius, -1 = unavailable
    @Published var gpuTemp: Double = -1
    var isAvailable: Bool { cpuTemp >= 0 || gpuTemp >= 0 }

    private var smcOpened = false
    private var activeCpuKeys: [String] = []
    private var activeGpuKeys: [String] = []

    // Key prefixes that indicate CPU temperature sensors
    // Tp = CPU performance/die, Te = CPU efficiency, Tf = M3 CPU cores
    // TC = Intel CPU, TCAD = Intel CPU die
    private static let cpuPrefixes = ["Tp", "Te", "Tf", "TC"]

    // Key prefixes that indicate GPU temperature sensors
    // Tg = Apple/Intel GPU, TG = Intel/AMD discrete GPU
    private static let gpuPrefixes = ["Tg", "TG"]

    init() {
        smcOpened = smc_open()
        if !smcOpened {
            log.info("SMC not available — sensor monitoring disabled")
            return
        }

        // Dynamically enumerate all SMC keys and discover temperature sensors
        let keyCount = smc_get_key_count()
        if keyCount == 0 {
            log.info("No SMC keys found — sensor monitoring disabled")
            return
        }

        var keyBuf = [CChar](repeating: 0, count: 5)
        for i: UInt32 in 0..<keyCount {
            guard smc_get_key_at_index(i, &keyBuf) else { continue }
            guard keyBuf[0] == 0x54 else { continue } // 'T' prefix only
            let key = String(cString: keyBuf)

            let temp = smc_get_temperature(key)
            guard temp > 0 && temp < 120 else { continue }

            if Self.cpuPrefixes.contains(where: { key.hasPrefix($0) }) {
                activeCpuKeys.append(key)
            } else if Self.gpuPrefixes.contains(where: { key.hasPrefix($0) }) {
                activeGpuKeys.append(key)
            }
        }

        log.info("Found \(self.activeCpuKeys.count) CPU temp sensors, \(self.activeGpuKeys.count) GPU temp sensors")
    }

    deinit {
        if smcOpened { smc_close() }
    }

    func read() {
        guard smcOpened else { return }

        if !activeCpuKeys.isEmpty {
            var sum = 0.0
            var count = 0
            for key in activeCpuKeys {
                let temp = smc_get_temperature(key)
                if temp > 0 && temp < 120 {
                    sum += temp
                    count += 1
                }
            }
            cpuTemp = count > 0 ? sum / Double(count) : -1
        }

        if !activeGpuKeys.isEmpty {
            var sum = 0.0
            var count = 0
            for key in activeGpuKeys {
                let temp = smc_get_temperature(key)
                if temp > 0 && temp < 120 {
                    sum += temp
                    count += 1
                }
            }
            gpuTemp = count > 0 ? sum / Double(count) : -1
        }
    }
}
