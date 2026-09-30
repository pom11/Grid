import Testing
import Foundation
@testable import Grid

@Test func zoneRoundTrip() throws {
    let zone = Zone(
        id: UUID(),
        name: "Terminal",
        gridSelection: GridRect(x: 0, y: 0, width: 12, height: 6),
        hotkey: nil,
        displayIndex: nil
    )
    let data = try JSONEncoder().encode(zone)
    let decoded = try JSONDecoder().decode(Zone.self, from: data)
    #expect(decoded.name == "Terminal")
    #expect(decoded.gridSelection.width == 12)
}

@Test func gridConfigDefaults() {
    let config = GridConfig()
    #expect(config.columns == 32)
    #expect(config.rows == 18)
    #expect(config.margin == 6)
    #expect(config.preset == .standard)
}

@Test func gridConfigPresets() {
    #expect(GridPreset.standard.columns == 32)
    #expect(GridPreset.standard.rows == 18)
    #expect(GridPreset.wide.columns == 42)
    #expect(GridPreset.wide.rows == 18)
    #expect(GridPreset.ultrawide.columns == 48)
    #expect(GridPreset.ultrawide.rows == 18)
    #expect(GridPreset.superultrawide.columns == 56)
    #expect(GridPreset.superultrawide.rows == 18)
}

@Test func gridRectValidation() {
    let config = GridConfig() // 32x18
    let valid = GridRect(x: 0, y: 0, width: 6, height: 4)
    #expect(valid.isValid(in: config))

    let outOfBounds = GridRect(x: 30, y: 10, width: 6, height: 4)
    #expect(!outOfBounds.isValid(in: config))

    let zeroWidth = GridRect(x: 0, y: 0, width: 0, height: 4)
    #expect(!zeroWidth.isValid(in: config))
}
