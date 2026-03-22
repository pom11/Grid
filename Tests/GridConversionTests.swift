import Testing
import Foundation
import CoreGraphics
@testable import Grid

@Test func fullScreenZone() {
    let config = GridConfig.basic // 12x8
    let screen = CGRect(x: 0, y: 0, width: 1200, height: 800)
    let zone = GridRect(x: 0, y: 0, width: 12, height: 8)
    let rect = zone.toScreenRect(in: screen, config: config)

    // Full screen with 3pt inset on each side (margin/2 = 3)
    #expect(rect.origin.x == 3)
    #expect(rect.origin.y == 3)
    #expect(rect.width == 1194)
    #expect(rect.height == 794)
}

@Test func leftHalfZone() {
    let config = GridConfig.basic
    let screen = CGRect(x: 0, y: 0, width: 1200, height: 800)
    let zone = GridRect(x: 0, y: 0, width: 6, height: 8)
    let rect = zone.toScreenRect(in: screen, config: config)

    #expect(rect.origin.x == 3)
    #expect(rect.width == 594)
}

@Test func fitTightToEdges() {
    var config = GridConfig.basic
    config.fitTightToEdges = true
    let screen = CGRect(x: 0, y: 0, width: 1200, height: 800)

    // Left half — left edge is tight, right edge has margin
    let leftHalf = GridRect(x: 0, y: 0, width: 6, height: 8)
    let leftRect = leftHalf.toScreenRect(in: screen, config: config)
    #expect(leftRect.origin.x == 0) // tight to left edge
    #expect(leftRect.width == 597) // 600 - 3 (right margin only)

    // Right half — left edge has margin, right edge is tight
    let rightHalf = GridRect(x: 6, y: 0, width: 6, height: 8)
    let rightRect = rightHalf.toScreenRect(in: screen, config: config)
    #expect(rightRect.origin.x == 603) // 600 + 3
    #expect(rightRect.width == 597)
}

@Test func secondDisplayOffset() {
    let config = GridConfig.basic
    let screen = CGRect(x: 1440, y: 0, width: 1200, height: 800)
    let zone = GridRect(x: 0, y: 0, width: 6, height: 4)
    let rect = zone.toScreenRect(in: screen, config: config)

    #expect(rect.origin.x == 1443) // 1440 + margin/2
    #expect(rect.origin.y == 3)
}

@Test func portraitGridConfig() {
    let landscape = GridConfig.fine // 24x12
    let portrait = landscape.portrait
    #expect(portrait.columns == 12)
    #expect(portrait.rows == 24)
}
