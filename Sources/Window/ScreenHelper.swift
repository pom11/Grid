import AppKit
import os.log

private let log = Logger(subsystem: "ro.pom.grid", category: "screen")

enum ScreenHelper {
    static var sortedScreens: [NSScreen] {
        NSScreen.screens.sorted { a, b in
            if a.frame.origin.x != b.frame.origin.x {
                return a.frame.origin.x < b.frame.origin.x
            }
            return a.frame.origin.y < b.frame.origin.y
        }
    }

    static func screen(for point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }

    static func screen(for frame: CGRect) -> NSScreen? {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return screen(for: center) ?? NSScreen.main
    }

    static func isPortrait(_ screen: NSScreen) -> Bool {
        screen.frame.height > screen.frame.width
    }

    static func adjacentScreen(from current: NSScreen, direction: Int) -> NSScreen? {
        let screens = sortedScreens
        guard screens.count > 1 else { return nil }
        guard let idx = screens.firstIndex(of: current) else { return nil }
        let newIdx = (idx + direction + screens.count) % screens.count
        return screens[newIdx]
    }

    static func relativeRect(from frame: CGRect, sourceScreen: NSScreen, targetScreen: NSScreen) -> CGRect {
        let src = sourceScreen.visibleFrame
        let dst = targetScreen.visibleFrame

        let relX = (frame.origin.x - src.origin.x) / src.width
        let relY = (frame.origin.y - src.origin.y) / src.height
        let relW = frame.width / src.width
        let relH = frame.height / src.height

        return CGRect(
            x: dst.origin.x + relX * dst.width,
            y: dst.origin.y + relY * dst.height,
            width: relW * dst.width,
            height: relH * dst.height
        )
    }
}
