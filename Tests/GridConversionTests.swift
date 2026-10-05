import Testing
import AppKit
import Foundation
import CoreGraphics
@testable import Grid

/// toScreenRect converts into AX (top-left origin) coordinates, translating
/// y anchored to the MAIN display's full height (NSScreen.screens.first —
/// AppKit guarantees that is the main display, since Cocoa's global origin
/// (0,0) is the bottom-left of main). Mirror the source's convenience overload
/// so these host-dependent assertions track the shipped code.
private func axVisibleY(for screen: CGRect) -> CGFloat {
    let mainHeight = NSScreen.screens.first?.frame.height ?? screen.height
    return mainHeight - screen.origin.y - screen.height
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

// v1.1.5 REGRESSION (fixed v1.1.6): snapping a secondary display that is
// TALLER than the main display using the target's OWN height instead of the
// main display's anchored every window too low — a huge dead gap above it.
// These use the pure overload so they are fully host-independent.
//
// Layout: main 1440x900 (30pt menu bar, Dock hidden → visible 1440x870 at
// Cocoa (0,0)); external 1920x1200 right of it, top-aligned: frame Cocoa
// origin (1440, -300) (frame top = main frame top = y 900), its own 30pt
// menu bar → visible (1440, -300, 1920, 1170).
@Test func tallerSecondaryDisplaySnapsToMainAnchoredY() {
    let config = GridConfig() // 32x18, margin 6
    let mainHeight: CGFloat = 900
    let externalVisible = CGRect(x: 1440, y: -300, width: 1920, height: 1170)
    let zone = GridRect(x: 0, y: 0, width: 16, height: 9) // top-left quarter

    let rect = zone.toScreenRect(in: externalVisible, config: config, mainDisplayHeight: mainHeight)

    // Correct (main-anchored): axVisibleY = 900 - (-300) - 1170 = 30 (just
    // below the external's own menu bar); zone y=0 row → y = 30 + 6 margin = 36.
    #expect(rect.origin.y == 36)
    #expect(rect.origin.x == 1446)
    // v1.1.5 formula anchored to the target's own height 1200 computed
    // axVisibleY = 1200 + 300 - 1170 = 330 → row-0 windows at y 336 (300pt gap).
    #expect(rect.origin.y != 336)
}

// Counterpart: a SHORTER secondary (own height < main) was snapped too HIGH
// (into/above the menu bar) by the v1.1.5 formula.
@Test func shorterSecondaryDisplaySnapsToMainAnchoredY() {
    let config = GridConfig()
    let mainHeight: CGFloat = 1080
    // External 1200x800 top-aligned right of a 1920x1080 main: frame Cocoa
    // origin (1920, 280), own 30pt menu bar → visible (1920, 280, 1200, 770).
    let externalVisible = CGRect(x: 1920, y: 280, width: 1200, height: 770)
    let zone = GridRect(x: 0, y: 0, width: 32, height: 18) // full external

    let rect = zone.toScreenRect(in: externalVisible, config: config, mainDisplayHeight: mainHeight)

    // Correct: axVisibleY = 1080 - 280 - 770 = 30 → y = 36; inset 6 all edges.
    #expect(rect.origin.y == 36)
    #expect(rect.origin.x == 1926)
    #expect(rect.width == 1188)
    #expect(rect.height == 758)
    // v1.1.5 own-height formula: axVisibleY = 800 - 280 - 770 = -250 → y = -244.
    #expect(rect.origin.y != -244)
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
