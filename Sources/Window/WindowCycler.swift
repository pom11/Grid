import AppKit
import os.log

private let log = Logger(subsystem: "ro.pom.grid", category: "cycler")

enum WindowCycler {
    static func nextIndex(current: Int, count: Int, direction: Int) -> Int {
        guard count > 0 else { return 0 }
        return (current + direction + count) % count
    }

    static func cycleFocus(direction: Int) {
        guard AccessibilityEngine.isTrusted else { return }

        let windows = AccessibilityEngine.listWindows()
        guard windows.count > 1 else { return }

        let sorted = windows.sorted { a, b in
            if a.frame.origin.x != b.frame.origin.x {
                return a.frame.origin.x < b.frame.origin.x
            }
            return a.frame.origin.y < b.frame.origin.y
        }

        guard let focused = AccessibilityEngine.getFocusedWindow() else {
            AccessibilityEngine.focusWindow(sorted[0])
            AccessibilityEngine.warpCursor(to: sorted[0].frame)
            return
        }

        let currentIdx = sorted.firstIndex { w in
            CFEqual(w.windowElement, focused.windowElement)
        } ?? 0

        let nextIdx = nextIndex(current: currentIdx, count: sorted.count, direction: direction)
        let target = sorted[nextIdx]
        AccessibilityEngine.focusWindow(target)
        AccessibilityEngine.warpCursor(to: target.frame)
        log.debug("Cycled focus to: \(target.appName) - \(target.title)")
    }
}
