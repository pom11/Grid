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
    let config = GridConfig.basic
    #expect(config.columns == 12)
    #expect(config.rows == 8)
    #expect(config.margin == 6)
    #expect(config.fitTightToEdges == false)
}

@Test func gridConfigPresets() {
    #expect(GridConfig.fine.columns == 24)
    #expect(GridConfig.fine.rows == 12)
    #expect(GridConfig.ultraFine.columns == 32)
    #expect(GridConfig.ultraFine.rows == 18)
}

@Test func gridRectValidation() {
    let config = GridConfig.basic // 12x8
    let valid = GridRect(x: 0, y: 0, width: 6, height: 4)
    #expect(valid.isValid(in: config))

    let outOfBounds = GridRect(x: 10, y: 6, width: 6, height: 4)
    #expect(!outOfBounds.isValid(in: config))

    let zeroWidth = GridRect(x: 0, y: 0, width: 0, height: 4)
    #expect(!zeroWidth.isValid(in: config))
}
