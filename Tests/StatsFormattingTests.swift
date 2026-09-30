import Testing
import Foundation
@testable import Grid

@Test func formatPercentage() {
    #expect(StatsFormatter.percentage(0.05) == "5%")
    #expect(StatsFormatter.percentage(0.234) == "23%")
    #expect(StatsFormatter.percentage(1.0) == "100%")
}

@Test func formatMemoryGB() {
    #expect(StatsFormatter.memoryGB(7_340_032 * 1024) == "7.34")
    #expect(StatsFormatter.memoryGB(8_660_992 * 1024) == "8.66")
}

@Test func formatDiskGB() {
    #expect(StatsFormatter.diskGB(250_000_000_000) == "250.0")
    #expect(StatsFormatter.diskGB(244_500_000_000) == "244.5")
}

@Test func formatNetworkSpeed() {
    #expect(StatsFormatter.networkSpeed(0) == "0")
    #expect(StatsFormatter.networkSpeed(1024) == "1.0K")
    #expect(StatsFormatter.networkSpeed(1_500_000) == "1.5M")
    #expect(StatsFormatter.networkSpeed(2_500_000_000) == "2.5G")
}

@Test func formatTemperature() {
    #expect(StatsFormatter.temperature(37.4) == "37°")
    #expect(StatsFormatter.temperature(34.8) == "35°")
    #expect(StatsFormatter.temperature(-1.0) == "--")
}
