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
