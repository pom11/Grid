import Testing
import Foundation
@testable import Grid

@Test func keyComboDisplayString() {
    let combo = KeyCombo(keyCode: 0x00, modifiers: 0x0100 | 0x0200) // cmdKey | shiftKey
    let display = combo.displayString
    #expect(display.contains("⇧"))
    #expect(display.contains("⌘"))
    #expect(display.contains("A"))
}

@Test func keyComboRoundTrip() throws {
    let combo = KeyCombo(keyCode: 0x7A, modifiers: 0x0100) // Cmd+F1
    let data = try JSONEncoder().encode(combo)
    let decoded = try JSONDecoder().decode(KeyCombo.self, from: data)
    #expect(decoded == combo)
}

@Test func fixedSlotRawValues() {
    #expect(Slot.focusNext.rawValue == 1)
    #expect(Slot.focusPrevious.rawValue == 2)
    #expect(Slot.moveNextDisplay.rawValue == 3)
    #expect(Slot.movePrevDisplay.rawValue == 4)
}

@Test func zoneSlotId() {
    let id = Slot.zoneSlotId(for: 0)
    #expect(id == 100)
    let id5 = Slot.zoneSlotId(for: 5)
    #expect(id5 == 105)
}

// Fix 4: findCollision() was dead code — never called. We wire it into
// HotKeyRecorderView at assignment time; this test pins the detector's behavior
// so it is exercised. It reads ZoneStore.shared.zones in memory (no disk save)
// and restores the prior array, staying hermetic. The probe combo is an exotic
// F20 chord that no sane saved fixed-slot config will use, so the fixed-slot
// half of the scan cannot flake this test.
@Suite struct HotKeyCollisionTests {

    @Test func detectsZoneCollision_andExcludesOwnZone() {
        let store = ZoneStore.shared
        let original = store.zones

        let probe = KeyCombo(
            keyCode: 0x5A, // F20
            modifiers: 0x1B00 // control(0x1000) | option(0x0800) | shift(0x0200) | cmd(0x0100)
        )
        let zone0 = Zone(
            id: UUID(),
            name: "Collision Probe",
            gridSelection: GridRect(x: 0, y: 0, width: 1, height: 1),
            hotkey: probe,
            displayIndex: nil
        )
        store.zones = [zone0]
        defer { store.zones = original }

        // The probe is owned by zone slot 100 (zone index 0).
        let zoneSlotId = Slot.zoneSlotId(for: 0)

        // Without excluding the owner, the collision is reported.
        let collision = HotKeyManager.shared.findCollision(probe)
        #expect(collision == "Zone: Collision Probe")

        // Excluding the owning zone's slot clears the conflict (unless a saved
        // fixed slot coincidentally holds this exotic F20 chord — vanishingly
        // unlikely, and that would be a genuine conflict anyway).
        #expect(HotKeyManager.shared.findCollision(probe, excludingId: zoneSlotId) == nil)
    }
}
