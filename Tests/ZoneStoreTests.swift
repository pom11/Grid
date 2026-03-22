import Testing
import Foundation
@testable import Grid

@Test func saveAndLoadZones() throws {
    let tmpDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    let file = tmpDir.appendingPathComponent("zones.json")

    let store = ZoneStore(fileURL: file)
    let zone = Zone(
        id: UUID(),
        name: "Browser",
        gridSelection: GridRect(x: 0, y: 0, width: 12, height: 8),
        hotkey: nil,
        displayIndex: nil
    )
    store.zones.append(zone)
    store.save()

    let store2 = ZoneStore(fileURL: file)
    store2.load()
    #expect(store2.zones.count == 1)
    #expect(store2.zones[0].name == "Browser")

    try FileManager.default.removeItem(at: tmpDir)
}

@Test func emptyFileLoadsEmpty() {
    let nonexistent = FileManager.default.temporaryDirectory
        .appendingPathComponent("nonexistent/zones.json")
    let store = ZoneStore(fileURL: nonexistent)
    store.load()
    #expect(store.zones.isEmpty)
}

@Test func addAndRemoveZone() throws {
    let tmpDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    let file = tmpDir.appendingPathComponent("zones.json")

    let store = ZoneStore(fileURL: file)
    let id = UUID()
    store.zones.append(Zone(
        id: id, name: "Test",
        gridSelection: GridRect(x: 0, y: 0, width: 6, height: 4),
        hotkey: nil, displayIndex: nil
    ))
    store.save()
    #expect(store.zones.count == 1)

    store.zones.removeAll { $0.id == id }
    store.save()

    let store2 = ZoneStore(fileURL: file)
    store2.load()
    #expect(store2.zones.isEmpty)

    try FileManager.default.removeItem(at: tmpDir)
}
