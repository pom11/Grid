import Foundation
import AppKit
import CoreGraphics
import os.log

private let log = Logger(subsystem: "ro.pom.grid", category: "zone")

struct Zone: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var gridSelection: GridRect
    var hotkey: KeyCombo?
    var displayIndex: Int?
}

struct GridRect: Codable, Equatable {
    var x: Int
    var y: Int
    var width: Int
    var height: Int

    func isValid(in config: GridConfig) -> Bool {
        width > 0 && height > 0 &&
        x >= 0 && y >= 0 &&
        x + width <= config.columns &&
        y + height <= config.rows
    }

    /// Convert grid coordinates to screen CGRect in AX coordinates (top-left origin)
    func toScreenRect(in screenFrame: CGRect, config: GridConfig) -> CGRect {
        // screenFrame is NSScreen.visibleFrame in Cocoa coords (bottom-left origin).
        // AX API uses Quartz coords (top-left of main display, y increases downward).
        let mainScreenHeight = NSScreen.screens.first?.frame.height ?? screenFrame.height

        // Convert visibleFrame to AX coords
        let axVisibleY = mainScreenHeight - screenFrame.origin.y - screenFrame.height

        let cellW = screenFrame.width / CGFloat(config.columns)
        let cellH = screenFrame.height / CGFloat(config.rows)

        // Grid y=0 is top row, which maps to small AX y values
        var rect = CGRect(
            x: screenFrame.origin.x + CGFloat(x) * cellW,
            y: axVisibleY + CGFloat(y) * cellH,
            width: CGFloat(width) * cellW,
            height: CGFloat(height) * cellH
        )

        // Screen edges get full margin, inner edges get half (so two adjacent = full)
        let m = config.margin
        let insetLeft: CGFloat = x == 0 ? m : m / 2
        let insetRight: CGFloat = (x + width) == config.columns ? m : m / 2
        let insetTop: CGFloat = y == 0 ? m : m / 2
        let insetBottom: CGFloat = (y + height) == config.rows ? m : m / 2
        rect.origin.x += insetLeft
        rect.origin.y += insetTop
        rect.size.width -= insetLeft + insetRight
        rect.size.height -= insetTop + insetBottom

        return rect
    }
}

struct GridConfig: Codable, Equatable, Hashable {
    var columns: Int = 32
    var rows: Int = 18
    var margin: CGFloat = 6

    static let `default` = GridConfig()

    init(columns: Int = 32, rows: Int = 18, margin: CGFloat = 6) {
        self.columns = columns
        self.rows = rows
        self.margin = margin
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        columns = try c.decodeIfPresent(Int.self, forKey: .columns) ?? 32
        rows = try c.decodeIfPresent(Int.self, forKey: .rows) ?? 18
        margin = try c.decodeIfPresent(CGFloat.self, forKey: .margin) ?? 6
    }

    /// Swap columns/rows for portrait displays
    var portrait: GridConfig {
        GridConfig(columns: rows, rows: columns, margin: margin)
    }
}
