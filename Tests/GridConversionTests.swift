import Testing
import AppKit
import Foundation
import CoreGraphics
@testable import Grid

/// toScreenRect converts into AX (top-left origin) coordinates, translating
/// y using the target screen's own full frame height. Compute the expected
/// translation the same way the source does (look up the NSScreen whose
/// visibleFrame matches; fall back to the passed-in visibleFrame height) so
/// these assertions are host-independent — the synthetic rects never match a
/// real display, so the fallback path is always exercised.
private func axVisibleY(for screen: CGRect) -> CGFloat {
    let fullFrameHeight = NSScreen.screens.first { $0.visibleFrame == screen }?.frame.height
        ?? screen.height
    return fullFrameHeight - screen.origin.y - screen.height
}

@Test func fullScreenZone() {
    let config = GridConfig() // 32x18
    let screen = CGRect(x: 0, y: 0, width: 1200, height: 800)
    let zone = GridRect(x: 0, y: 0, width: 32, height: 18)
    let rect = zone.toScreenRect(in: screen, config: config)

    // Full screen with 6pt inset on each side (margin = 6, full on screen edges)
    #expect(rect.origin.x == 6)
    #expect(rect.origin.y == axVisibleY(for: screen) + 6)
    #expect(rect.width == 1188)  // 1200 - 6 - 6
    #expect(rect.height == 788)  // 800 - 6 - 6
}

@Test func leftHalfZone() {
    let config = GridConfig() // 32x18
    let screen = CGRect(x: 0, y: 0, width: 1200, height: 800)
    let zone = GridRect(x: 0, y: 0, width: 16, height: 18)
    let rect = zone.toScreenRect(in: screen, config: config)

    // Left half: left edge is a screen edge (full margin), right edge is inner (half margin)
    #expect(rect.origin.x == 6)   // 0 + 6
    #expect(rect.width == 591)    // 600 - 6 - 3
}

@Test func secondDisplayOffset() {
    let config = GridConfig() // 32x18
    let screen = CGRect(x: 1440, y: 0, width: 1200, height: 800)
    let zone = GridRect(x: 0, y: 0, width: 16, height: 4)
    let rect = zone.toScreenRect(in: screen, config: config)

    #expect(rect.origin.x == 1446) // 1440 + margin (6)
    #expect(rect.origin.y == axVisibleY(for: screen) + 6)
}

@Test func portraitGridConfig() {
    let landscape = GridConfig() // 32x18
    let portrait = landscape.portrait
    #expect(portrait.columns == 18)
    #expect(portrait.rows == 32)
}

// Fix [3]: on a portrait monitor, a vertical-ready config must NOT double-swap.
// The per-display config with vertical=true already swapped via applyPreset
// (18 columns x 32 rows for the standard preset); re-applying the portrait
// transform would yield 32x18 and misplace windows. effectiveConfig guards it.
@Test func portraitScreenWithVerticalConfigKeepsVerticalDims() {
    // vertical=true standard preset → applyPreset gives 18x32
    var config = GridConfig(preset: .standard, vertical: true)
    config.applyPreset()
    #expect(config.columns == 18)
    #expect(config.rows == 32)

    // On a portrait screen the config must be used as-is (no second swap).
    let effective = WindowSnapper.effectiveConfig(isPortrait: true, config: config)
    #expect(effective.columns == 18)
    #expect(effective.rows == 32)
}

// Sanity: the same landscape config on a portrait screen still gets the
// portrait transform applied exactly once (18x32 for the standard preset),
// so the fix only suppresses the DOUBLE swap, not the intended one.
@Test func portraitScreenWithoutVerticalStillAppliesPortrait() {
    let config = GridConfig() // 32x18 landscape, vertical=false
    let effective = WindowSnapper.effectiveConfig(isPortrait: true, config: config)
    #expect(effective.columns == 18)
    #expect(effective.rows == 32)
}
