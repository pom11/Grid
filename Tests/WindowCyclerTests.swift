import Testing
import Foundation
import CoreGraphics
@testable import Grid

@Test func sortWindowsLeftToRight() {
    let frames = [
        CGRect(x: 800, y: 100, width: 400, height: 300),
        CGRect(x: 0, y: 100, width: 400, height: 300),
        CGRect(x: 1200, y: 100, width: 400, height: 300),
    ]

    let sorted = frames.sorted { a, b in
        if a.origin.x != b.origin.x { return a.origin.x < b.origin.x }
        return a.origin.y < b.origin.y
    }

    #expect(sorted[0].origin.x == 0)
    #expect(sorted[1].origin.x == 800)
    #expect(sorted[2].origin.x == 1200)
}

@Test func sortWindowsWithTiebreaker() {
    let frames = [
        CGRect(x: 0, y: 400, width: 400, height: 300),
        CGRect(x: 0, y: 0, width: 400, height: 300),
    ]

    let sorted = frames.sorted { a, b in
        if a.origin.x != b.origin.x { return a.origin.x < b.origin.x }
        return a.origin.y < b.origin.y
    }

    #expect(sorted[0].origin.y == 0)
    #expect(sorted[1].origin.y == 400)
}

@Test func cycleIndexWrapsAround() {
    let count = 3
    #expect(WindowCycler.nextIndex(current: 0, count: count, direction: 1) == 1)
    #expect(WindowCycler.nextIndex(current: 2, count: count, direction: 1) == 0)
    #expect(WindowCycler.nextIndex(current: 0, count: count, direction: -1) == 2)
}
