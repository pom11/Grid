import Foundation

enum StatsFormatter {
    static func percentage(_ value: Double) -> String {
        "\(Int(round(value * 100)))%"
    }

    static func memoryGB(_ bytes: UInt64) -> String {
        let kb = Double(bytes) / 1024.0
        let gb = kb / 1_000_000.0
        return String(format: "%.2f", gb)
    }

    static func diskGB(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_000_000_000.0
        return String(format: "%.1f", gb)
    }

    static func networkSpeed(_ bytesPerSec: UInt64) -> String {
        if bytesPerSec == 0 { return "0" }
        if bytesPerSec >= 1_000_000_000 {
            return String(format: "%.1fG", Double(bytesPerSec) / 1_000_000_000.0)
        }
        if bytesPerSec >= 1_000_000 {
            return String(format: "%.1fM", Double(bytesPerSec) / 1_000_000.0)
        }
        return String(format: "%.1fK", Double(bytesPerSec) / 1_000.0)
    }

    static func temperature(_ celsius: Double) -> String {
        if celsius < 0 { return "--" }
        return "\(Int(round(celsius)))°"
    }
}
