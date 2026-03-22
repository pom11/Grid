import Testing
import Foundation
import CoreGraphics
@testable import Grid

@Test func relativeRectPreservesPercentages() {
    let srcFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let dstFrame = CGRect(x: 1920, y: 0, width: 2560, height: 1440)

    let window = CGRect(x: 480, y: 270, width: 960, height: 540)

    let relX = (window.origin.x - srcFrame.origin.x) / srcFrame.width
    let relY = (window.origin.y - srcFrame.origin.y) / srcFrame.height
    let relW = window.width / srcFrame.width
    let relH = window.height / srcFrame.height

    let result = CGRect(
        x: dstFrame.origin.x + relX * dstFrame.width,
        y: dstFrame.origin.y + relY * dstFrame.height,
        width: relW * dstFrame.width,
        height: relH * dstFrame.height
    )

    #expect(abs(result.origin.x - 2560) < 1)
    #expect(abs(result.origin.y - 360) < 1)
    #expect(abs(result.width - 1280) < 1)
    #expect(abs(result.height - 720) < 1)
}
