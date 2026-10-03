import Foundation
import Darwin
import os.log

@MainActor
class NetworkReader: ObservableObject {
    @Published var uploadSpeed: UInt64 = 0
    @Published var downloadSpeed: UInt64 = 0

    private let logger = Logger(subsystem: "ro.pom.grid", category: "network")
    private var lastRead: (upload: UInt64, download: UInt64, time: Date)?

    func read() {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            logger.error("Failed to get network interfaces")
            return
        }

        defer { freeifaddrs(ifaddr) }

        var totalBytesIn: UInt64 = 0
        var totalBytesOut: UInt64 = 0
        var current = firstAddr

        while true {
            let name = String(cString: current.pointee.ifa_name)

            // Skip loopback plus VPN/tunnel/Apple-wireless interfaces. Physical
            // Ethernet/Wi-Fi (en*, bridge*, ...) all count; utun*, awdl*, llw*
            // (and lo0) would otherwise inflate the reported speeds with
            // looped tunnel traffic.
            let isVirtual = name == "lo0"
                || name.hasPrefix("utun")   // VPN tunnels (WireGuard, OpenVPN, ...)
                || name.hasPrefix("awdl")   // Apple Wireless Direct Link
                || name.hasPrefix("llw")    // Low-Latency WLAN (infrastructure)
                || name.hasPrefix("ipsec")
                || name.hasPrefix("ppp")
                || name.hasPrefix("gif")
                || name.hasPrefix("stf")

            if !isVirtual, let addr = current.pointee.ifa_addr,
               addr.pointee.sa_family == UInt8(AF_LINK) {

                if let networkData = current.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) {
                    totalBytesIn += UInt64(networkData.pointee.ifi_ibytes)
                    totalBytesOut += UInt64(networkData.pointee.ifi_obytes)
                }
            }

            if let next = current.pointee.ifa_next {
                current = next
            } else {
                break
            }
        }

        let now = Date()

        if let last = lastRead {
            let timeDelta = now.timeIntervalSince(last.time)

            if timeDelta > 0 {
                let bytesInDelta = totalBytesIn > last.download ? totalBytesIn - last.download : 0
                let bytesOutDelta = totalBytesOut > last.upload ? totalBytesOut - last.upload : 0

                downloadSpeed = UInt64(Double(bytesInDelta) / timeDelta)
                uploadSpeed = UInt64(Double(bytesOutDelta) / timeDelta)
            }
        }

        lastRead = (upload: totalBytesOut, download: totalBytesIn, time: now)
    }
}
