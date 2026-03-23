import Foundation
import Darwin.Mach
import os.log

@MainActor
class RAMReader: ObservableObject {
    @Published var free: UInt64 = 0
    @Published var used: UInt64 = 0

    let total: UInt64

    private let logger = Logger(subsystem: "ro.pom.grid", category: "ram")
    private let hostPort = mach_host_self()

    init() {
        total = ProcessInfo.processInfo.physicalMemory
    }

    func read() {
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var stats = vm_statistics64_data_t()

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(
                    hostPort,
                    HOST_VM_INFO64,
                    $0,
                    &size
                )
            }
        }

        guard result == KERN_SUCCESS else {
            logger.error("Failed to get RAM info: \(result)")
            return
        }

        let pageSize = UInt64(vm_kernel_page_size)
        let freePages = UInt64(stats.free_count)
        let activePages = UInt64(stats.active_count)
        let inactivePages = UInt64(stats.inactive_count)
        let wiredPages = UInt64(stats.wire_count)
        let compressedPages = UInt64(stats.compressor_page_count)

        free = freePages * pageSize
        used = (activePages + wiredPages + compressedPages) * pageSize
    }
}
