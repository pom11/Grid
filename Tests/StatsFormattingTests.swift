import Testing
import Foundation
@testable import Grid

@Test func formatPercentage() {
    #expect(StatsFormatter.percentage(0.05) == "5%")
    #expect(StatsFormatter.percentage(0.234) == "23%")
    #expect(StatsFormatter.percentage(1.0) == "100%")
}

@Test func formatMemoryGB() {
    #expect(StatsFormatter.memoryGB(7_340_032 * 1024) == "7.34 GB")
    #expect(StatsFormatter.memoryGB(8_660_992 * 1024) == "8.66 GB")
}

@Test func formatDiskGB() {
    #expect(StatsFormatter.diskGB(250_000_000_000) == "250.0 GB")
    #expect(StatsFormatter.diskGB(244_500_000_000) == "244.5 GB")
}

@Test func formatNetworkSpeed() {
    #expect(StatsFormatter.networkSpeed(0) == "0 K/s")
    #expect(StatsFormatter.networkSpeed(1024) == "1.0 K/s")
    #expect(StatsFormatter.networkSpeed(1_500_000) == "1.5 M/s")
    #expect(StatsFormatter.networkSpeed(2_500_000_000) == "2.5 G/s")
}

@Test func formatTemperature() {
    #expect(StatsFormatter.temperature(37.4) == "37°")
    #expect(StatsFormatter.temperature(34.8) == "35°")
    #expect(StatsFormatter.temperature(-1.0) == "--")
}
