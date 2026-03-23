import AppKit
import os.log

private let log = Logger(subsystem: "ro.pom.grid", category: "snapper")

enum WindowSnapper {
    static func snap(to zone: Zone, appConfig: AppConfig) {
        guard AccessibilityEngine.isTrusted else { return }
        guard let window = AccessibilityEngine.getFocusedWindow() else {
            log.debug("No focused window to snap")
            return
        }

        let targetScreen: NSScreen
        if let displayIndex = zone.displayIndex {
            let screens = ScreenHelper.sortedScreens
            if displayIndex < screens.count {
                targetScreen = screens[displayIndex]
            } else {
                log.debug("Display \(displayIndex) not available, falling back to main")
                targetScreen = NSScreen.main ?? window.screen
            }
        } else {
            targetScreen = window.screen
        }

        let config: GridConfig
        if let zoneDisplay = zone.displayIndex {
            config = appConfig.gridConfig(for: zoneDisplay)
        } else {
            config = appConfig.grid
        }
        let effectiveConfig = ScreenHelper.isPortrait(targetScreen) ? config.portrait : config

        let screenRect = zone.gridSelection.toScreenRect(
            in: targetScreen.visibleFrame,
            config: effectiveConfig
        )

        NSLog("WindowSnapper: snapping '%@' to zone '%@' rect=%@ margin=%.1f", window.appName, zone.name, screenRect.debugDescription, effectiveConfig.margin)
        AccessibilityEngine.moveWindow(window, to: screenRect)
    }

    static func moveToDisplay(direction: Int) {
        guard AccessibilityEngine.isTrusted else { return }
        guard let window = AccessibilityEngine.getFocusedWindow() else { return }
        guard let targetScreen = ScreenHelper.adjacentScreen(from: window.screen, direction: direction) else {
            log.debug("No adjacent display in direction \(direction)")
            return
        }

        let newRect = ScreenHelper.relativeRect(
            from: window.frame,
            sourceScreen: window.screen,
            targetScreen: targetScreen
        )

        AccessibilityEngine.moveWindow(window, to: newRect)
        log.debug("Moved \(window.appName) to \(direction > 0 ? "next" : "previous") display")
    }
}
