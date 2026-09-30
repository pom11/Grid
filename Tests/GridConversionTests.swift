import Testing
import AppKit
import Foundation
import CoreGraphics
@testable import Grid

/// toScreenRect converts into AX (top-left origin) coordinates, translating
/// y using the real main display height. Compute the expected translation the
/// same way the source does so these assertions are host-independent.
private func axVisibleY(for screen: CGRect) -> CGFloat {
    let mainScreenHeight = NSScreen.screens.first?.frame.height ?? screen.height
    return mainScreenHeight - screen.origin.y - screen.height
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
