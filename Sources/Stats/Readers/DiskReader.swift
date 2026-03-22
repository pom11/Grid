import Foundation
import os.log

@MainActor
class DiskReader: ObservableObject {
    @Published var free: UInt64 = 0
    @Published var used: UInt64 = 0
    @Published var total: UInt64 = 0

    private let logger = Logger(subsystem: "ro.pom.grid", category: "disk")

    func read() {
        let url = URL(fileURLWithPath: "/")

        do {
            let values = try url.resourceValues(forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey
            ])

            if let totalCapacity = values.volumeTotalCapacity,
               let availableCapacity = values.volumeAvailableCapacityForImportantUsage {
                total = UInt64(totalCapacity)
                free = UInt64(availableCapacity)
                used = total - free
            }
        } catch {
            logger.error("Failed to get disk info: \(error.localizedDescription)")
        }
    }
}
