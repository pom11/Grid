//
//  WindowSnapper.swift
//  Grid
//
//  Zone snapping + cross-display moves. Every early exit goes through
//  GridDiagnostics.report so `log show --predicate 'process == "Grid"'` is a real
//  diagnostic channel in the field (see GridDiagnostics for why plain NSLog/os-log
//  .debug are invisible to that query on macOS 27).
//

import AppKit

enum WindowSnapper {
    /// Shared front door for both hotkey actions: resolve the target window once, and
    /// report why when there is none. A snap press that does nothing is otherwise invisible.
    private static func targetWindow(action: String) -> WindowModel? {
        guard AccessibilityEngine.isTrusted else {
            GridDiagnostics.report("Grid \(action): accessibility not trusted — hotkey ignored")
            return nil
        }
        guard let window = AccessibilityEngine.getFocusedWindow() else {
            GridDiagnostics.report("Grid \(action): no usable window — hotkey ignored")
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
                GridDiagnostics.report("Grid snap: display index \(displayIndex) not available (have \(screens.count)) — falling back to main")
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

        // Prefix kept as "WindowSnapper: snapping" — the string the v1.1.4/1.1.6 field
        // investigation grepped for, so past and future log captures stay comparable.
        GridDiagnostics.note("WindowSnapper: snapping '\(window.appName)' to zone '\(zone.name)' rect=\(screenRect.debugDescription) margin=\(String(format: "%.1f", effectiveConfig.margin))")
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
            GridDiagnostics.report("Grid \(action): no adjacent display found (window on '\(window.screen.localizedName)') — hotkey ignored")
            return
        }

        let newRect = ScreenHelper.relativeRect(
            from: window.frame,
            sourceScreen: window.screen,
            targetScreen: targetScreen
        )

        GridDiagnostics.note("Grid \(action): '\(window.appName)' \(NSStringFromRect(window.frame)) -> target screen '\(targetScreen.localizedName)' rect=\(NSStringFromRect(newRect))")
        AccessibilityEngine.moveWindow(window, to: newRect)
    }
}
