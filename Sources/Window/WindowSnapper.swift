//
//  WindowSnapper.swift
//  Grid
//
//  Zone snapping + cross-display moves. Every early exit is logged with NSLog (not
//  os.log .debug, which is not persisted in release builds) so
//  `log show --predicate 'process == "Grid"'` is a real diagnostic channel in the field.
//

import AppKit

enum WindowSnapper {
    /// Shared front door for both hotkey actions: resolve the target window once, and NSLog
    /// why when there is none. A snap press that does nothing is otherwise invisible.
    private static func targetWindow(action: String) -> WindowModel? {
        guard AccessibilityEngine.isTrusted else {
            NSLog("Grid \(action): accessibility not trusted — hotkey ignored")
            return nil
        }
        guard let window = AccessibilityEngine.getFocusedWindow() else {
            NSLog("Grid \(action): no usable window — hotkey ignored")
            return nil
        }
        return window
    }

    static func snap(to zone: Zone, appConfig: AppConfig) {
        guard let window = targetWindow(action: "snap '\(zone.name)'") else { return }

        let targetScreen: NSScreen
        if let displayIndex = zone.displayIndex {
            let screens = ScreenHelper.sortedScreens
            if displayIndex < screens.count {
                targetScreen = screens[displayIndex]
            } else {
                NSLog("Grid snap: display index %d not available (have %d) — falling back to main",
                      displayIndex, screens.count)
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
        let effectiveConfig = Self.effectiveConfig(isPortrait: ScreenHelper.isPortrait(targetScreen), config: config)

        let screenRect = zone.gridSelection.toScreenRect(
            in: targetScreen.visibleFrame,
            config: effectiveConfig
        )

        NSLog("WindowSnapper: snapping '%@' to zone '%@' rect=%@ margin=%.1f", window.appName, zone.name, screenRect.debugDescription, effectiveConfig.margin)
        AccessibilityEngine.moveWindow(window, to: screenRect)
    }

    /// Resolve the config actually used to snap on a given screen.
    ///
    /// A per-display config with `vertical` already swapped columns/rows via
    /// `applyPreset`, so the portrait transform must NOT apply a second swap on
    /// a portrait monitor — that would yield e.g. 32x18 instead of 18x32 and
    /// misplace windows. Portrait adapts the LANDSCAPE preset only.
    static func effectiveConfig(isPortrait: Bool, config: GridConfig) -> GridConfig {
        (isPortrait && !config.vertical) ? config.portrait : config
    }

    static func moveToDisplay(direction: Int) {
        let action = "moveToDisplay \(direction > 0 ? "next" : "previous")"
        guard let window = targetWindow(action: action) else { return }
        guard let targetScreen = ScreenHelper.adjacentScreen(from: window.screen, direction: direction) else {
            NSLog("Grid %@: no adjacent display found (window on '%@') — hotkey ignored",
                  action, window.screen.localizedName)
            return
        }

        let newRect = ScreenHelper.relativeRect(
            from: window.frame,
            sourceScreen: window.screen,
            targetScreen: targetScreen
        )

        NSLog("Grid %@: '%@' %@ -> target screen '%@' rect=%@",
              action, window.appName, NSStringFromRect(window.frame),
              targetScreen.localizedName, NSStringFromRect(newRect))
        AccessibilityEngine.moveWindow(window, to: newRect)
    }
}
