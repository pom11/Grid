import Foundation
import Carbon
import os.log

private let log = Logger(subsystem: "ro.pom.grid", category: "hotkeys")

// MARK: - KeyCombo

struct KeyCombo: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    var displayString: String {
        var parts: [String] = []

        // Modifier symbols in standard macOS order
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }

        // Key name
        if let keyName = Self.keyNames[Int(keyCode)] {
            parts.append(keyName)
        } else {
            parts.append("?")
        }

        return parts.joined()
    }

    /// Convert Carbon modifiers to modern EventModifiers for registration
    func carbonModifiers() -> UInt32 {
        var result: UInt32 = 0
        if modifiers & UInt32(controlKey) != 0 { result |= UInt32(controlKey) }
        if modifiers & UInt32(optionKey) != 0 { result |= UInt32(optionKey) }
        if modifiers & UInt32(shiftKey) != 0 { result |= UInt32(shiftKey) }
        if modifiers & UInt32(cmdKey) != 0 { result |= UInt32(cmdKey) }
        return result
    }

    // MARK: Key Names Dictionary

    static let keyNames: [Int: String] = [
        // Letters A-Z
        0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H",
        0x05: "G", 0x06: "Z", 0x07: "X", 0x08: "C", 0x09: "V",
        0x0B: "B", 0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R",
        0x10: "Y", 0x11: "T", 0x12: "1", 0x13: "2", 0x14: "3",
        0x15: "4", 0x16: "6", 0x17: "5", 0x18: "=", 0x19: "9",
        0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0", 0x1E: "]",
        0x1F: "O", 0x20: "U", 0x21: "[", 0x22: "I", 0x23: "P",
        0x25: "L", 0x26: "J", 0x27: "'", 0x28: "K", 0x29: ";",
        0x2A: "\\", 0x2B: ",", 0x2C: "/", 0x2D: "N", 0x2E: "M",
        0x2F: ".",

        // Numbers and symbols
        0x52: "0", 0x53: "1", 0x54: "2", 0x55: "3", 0x56: "4",
        0x57: "5", 0x58: "6", 0x59: "7", 0x5B: "8", 0x5C: "9",

        // Function keys
        0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4",
        0x60: "F5", 0x61: "F6", 0x62: "F7", 0x64: "F8",
        0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12",
        0x69: "F13", 0x6B: "F14", 0x71: "F15", 0x6A: "F16",
        0x40: "F17", 0x4F: "F18", 0x50: "F19", 0x5A: "F20",

        // Arrows
        0x7E: "↑", 0x7D: "↓", 0x7B: "←", 0x7C: "→",

        // Special keys
        0x24: "↩", 0x30: "⇥", 0x31: "Space", 0x33: "⌫",
        0x35: "⎋", 0x75: "⌦", 0x73: "Home", 0x77: "End",
        0x74: "⇞", 0x79: "⇟",
    ]
}

// MARK: - Slot

enum Slot {
    case focusNext
    case focusPrevious
    case moveNextDisplay
    case movePrevDisplay
    case zone(Int)

    var rawValue: UInt32 {
        switch self {
        case .focusNext: return 1
        case .focusPrevious: return 2
        case .moveNextDisplay: return 3
        case .movePrevDisplay: return 4
        case .zone(let index): return UInt32(100 + index)
        }
    }

    static func zoneSlotId(for index: Int) -> UInt32 {
        return UInt32(100 + index)
    }

    var label: String {
        switch self {
        case .focusNext: return "Focus Next Window"
        case .focusPrevious: return "Focus Previous Window"
        case .moveNextDisplay: return "Move to Next Display"
        case .movePrevDisplay: return "Move to Previous Display"
        case .zone(let index): return "Zone \(index)"
        }
    }

    var description: String {
        label
    }
}

// MARK: - HotKeyManager

final class HotKeyManager {
    static let shared = HotKeyManager()

    private var handlers: [UInt32: () -> Void] = [:]
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?
    private let signature = OSType(0x47524400) // "GRD\0"

    private init() {
        installEventHandler()
    }

    deinit {
        for (_, ref) in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        if let handler = eventHandler {
            RemoveEventHandler(handler)
        }
    }

    // MARK: Event Handler Installation

    private func installEventHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { (_, event, userData) -> OSStatus in
            guard let event = event else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let err = GetEventParameter(
                event,
                UInt32(kEventParamDirectObject),
                UInt32(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard err == noErr else { return err }

            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData!).takeUnretainedValue()
            manager.handleHotKey(id: hotKeyID.id)
            return noErr
        }

        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType, userData, &eventHandler)
    }

    private func handleHotKey(id: UInt32) {
        log.debug("Hotkey triggered: \(id)")
        handlers[id]?()
    }

    // MARK: Registration

    func register(id: UInt32, combo: KeyCombo, handler: @escaping () -> Void) {
        unregister(id: id)

        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: id)

        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.carbonModifiers(),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status == noErr, let ref = hotKeyRef {
            hotKeyRefs[id] = ref
            handlers[id] = handler
            log.debug("Registered hotkey \(id): \(combo.displayString)")
        } else {
            log.error("Failed to register hotkey \(id): status \(status)")
        }
    }

    func register(slot: Slot, combo: KeyCombo, handler: @escaping () -> Void) {
        register(id: slot.rawValue, combo: combo, handler: handler)
    }

    func unregister(id: UInt32) {
        if let ref = hotKeyRefs.removeValue(forKey: id) {
            UnregisterEventHotKey(ref)
            log.debug("Unregistered Carbon hotkey \(id)")
        }
        handlers.removeValue(forKey: id)
    }

    func unregister(slot: Slot) {
        unregister(id: slot.rawValue)
    }

    // MARK: Collision Detection

    /// Check if a combo is already assigned to another slot
    func findCollision(_ combo: KeyCombo, excludingId: UInt32? = nil) -> String? {
        let fixedSlots: [Slot] = [.focusNext, .focusPrevious, .moveNextDisplay, .movePrevDisplay]
        for slot in fixedSlots {
            if let excluding = excludingId, slot.rawValue == excluding { continue }
            if let saved = savedCombo(for: slot), saved == combo {
                return slot.label
            }
        }

        // Check zone hotkeys in ZoneStore
        let zones = ZoneStore.shared.zones
        for (index, zone) in zones.enumerated() {
            let zoneId = Slot.zoneSlotId(for: index)
            if let excluding = excludingId, zoneId == excluding { continue }
            if let zoneCombo = zone.hotkey, zoneCombo == combo {
                return "Zone: \(zone.name)"
            }
        }

        return nil
    }

    // MARK: Persistence

    func savedCombo(for slot: Slot) -> KeyCombo? {
        let config = AppConfig.load()
        switch slot {
        case .focusNext: return config.hotkeys.focusNext
        case .focusPrevious: return config.hotkeys.focusPrevious
        case .moveNextDisplay: return config.hotkeys.moveNextDisplay
        case .movePrevDisplay: return config.hotkeys.movePrevDisplay
        case .zone: return nil
        }
    }

    func saveCombo(_ combo: KeyCombo?, for slot: Slot) {
        var config = AppConfig.load()
        switch slot {
        case .focusNext: config.hotkeys.focusNext = combo
        case .focusPrevious: config.hotkeys.focusPrevious = combo
        case .moveNextDisplay: config.hotkeys.moveNextDisplay = combo
        case .movePrevDisplay: config.hotkeys.movePrevDisplay = combo
        case .zone: return
        }
        config.save()
    }

    func saveZoneCombo(_ combo: KeyCombo?, forZoneIndex index: Int) {
        // Update zone in ZoneStore
        guard index < ZoneStore.shared.zones.count else { return }
        ZoneStore.shared.zones[index].hotkey = combo
        ZoneStore.shared.save()
    }
}
