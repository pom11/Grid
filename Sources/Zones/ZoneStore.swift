import Foundation
import Carbon
import os.log
import Combine

private let log = Logger(subsystem: "ro.pom.grid", category: "zones")

final class ZoneStore: ObservableObject {
    @Published var zones: [Zone] = []
    private let fileURL: URL

    static let shared = ZoneStore()

    convenience init() {
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/grid")
        let fileURL = configDir.appendingPathComponent("zones.json")
        self.init(fileURL: fileURL)
        load()
    }

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            zones = Self.defaultZones
            save()
            log.info("Created \(self.zones.count) default zones")
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            zones = try JSONDecoder().decode([Zone].self, from: data)
            log.debug("Loaded \(self.zones.count) zones")
        } catch {
            log.error("Failed to load zones: \(error.localizedDescription)")
            zones = Self.defaultZones
            save()
        }
    }

    // MARK: - Default Zones (⌥⌘ modifiers)

    private static let optCmd = UInt32(optionKey) | UInt32(cmdKey)

    private static let defaultZones: [Zone] = {
        // 32×18 grid
        let full = 32
        let half = 16
        let rows = 18
        let halfR = 9
        let third = 11      // 11 + 10 + 11 = 32
        let thirdMid = 10
        let twoThird = 21   // 32 - 11

        return [
            // Maximize
            z("Maximize",         0, 0,  full, rows,   0x24), // Enter

            // Halves
            z("Left",             0, 0,  half, rows,   0x7B), // ←
            z("Right",           half, 0, half, rows,   0x7C), // →
            z("Top",              0, 0,  full, halfR,   0x7E), // ↑
            z("Bottom",           0, halfR, full, halfR, 0x7D), // ↓

            // Quarters
            z("Top Left",        0, 0,     half, halfR, 0x29), // ;
            z("Top Right",      half, 0,   half, halfR, 0x27), // '
            z("Bottom Left",     0, halfR, half, halfR, 0x2B), // ,
            z("Bottom Right",   half, halfR, half, halfR, 0x2C), // /

            // Thirds
            z("Left Third",      0, 0,         third, rows,    0x0C), // Q
            z("Center Third",   third, 0,      thirdMid, rows, 0x0D), // W
            z("Right Third",    third + thirdMid, 0, third, rows, 0x0E), // E

            // Two Thirds
            z("Left Two Thirds",   0, 0,               twoThird, rows, 0x00), // A
            z("Center Two Thirds", (full - twoThird) / 2, 0, twoThird + 1, rows, 0x01), // S
            z("Right Two Thirds",  third, 0,           twoThird, rows, 0x02), // D
        ]
    }()

    private static func z(_ name: String, _ x: Int, _ y: Int, _ w: Int, _ h: Int, _ key: UInt32) -> Zone {
        Zone(
            id: UUID(),
            name: name,
            gridSelection: GridRect(x: x, y: y, width: w, height: h),
            hotkey: KeyCombo(keyCode: key, modifiers: optCmd),
            displayIndex: nil
        )
    }

    func save() {
        do {
            let dir = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(zones)
            try data.write(to: fileURL, options: .atomic)
            log.debug("Saved \(self.zones.count) zones")
        } catch {
            log.error("Failed to save zones: \(error.localizedDescription)")
        }
    }
}
