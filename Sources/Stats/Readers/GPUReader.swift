import Foundation
import Combine
import IOKit
import os.log

private let log = Logger(subsystem: "ro.pom.grid", category: "gpu")

final class GPUReader: ObservableObject {
    @Published var usage: Double = -1 // 0.0 to 1.0, -1 = unavailable
    var isAvailable: Bool { usage >= 0 }

    func read() {
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOAccelerator"),
            &iterator
        )
        guard result == KERN_SUCCESS else {
            log.debug("IOServiceGetMatchingServices failed: \(result)")
            return
        }
        defer { IOObjectRelease(iterator) }

        var entry: io_object_t = IOIteratorNext(iterator)
        while entry != 0 {
            defer {
                IOObjectRelease(entry)
                entry = IOIteratorNext(iterator)
            }

            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = properties?.takeRetainedValue() as? [String: Any],
                  let stats = dict["PerformanceStatistics"] as? [String: Any] else {
                continue
            }

            if let util = stats["Device Utilization %"] as? Int
                ?? stats["GPU Activity(%)"] as? Int {
                usage = min(Double(util), 100.0) / 100.0
                return
            }
        }

        // No accelerator found with utilization data
        if usage < 0 {
            log.info("GPU utilization not available via IOAccelerator")
        }
    }
}
