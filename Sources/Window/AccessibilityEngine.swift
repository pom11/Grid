import AppKit
import os.log

private let log = Logger(subsystem: "ro.pom.grid", category: "accessibility")

enum AccessibilityEngine {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func requestPermission() {
        if isTrusted { return }

        let alert = NSAlert()
        alert.messageText = "Accessibility Access Required"
        alert.informativeText = "Grid needs Accessibility access to manage windows. You'll be asked to grant permission in System Settings."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }
    }

    static func listWindows() -> [WindowModel] {
        guard isTrusted else {
            log.warning("listWindows called but not trusted")
            return []
        }

        var result: [WindowModel] = []
        let ownPID = ProcessInfo.processInfo.processIdentifier

        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular else { continue }
            guard app.processIdentifier != ownPID else { continue }

            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            var windowsValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue) == .success,
                  let windows = windowsValue as? [AXUIElement] else { continue }

            for window in windows {
                var subroleValue: CFTypeRef?
                AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subroleValue)
                let subrole = subroleValue as? String ?? ""
                guard subrole == "AXStandardWindow" else { continue }

                var minimizedValue: CFTypeRef?
                AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedValue)
                if let minimized = minimizedValue as? Bool, minimized { continue }

                var positionValue: CFTypeRef?
                guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success else { continue }
                var position = CGPoint.zero
                AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)

                var sizeValue: CFTypeRef?
                guard AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success else { continue }
                var size = CGSize.zero
                AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)

                var titleValue: CFTypeRef?
                AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue)
                let title = (titleValue as? String) ?? ""

                let frame = CGRect(origin: position, size: size)
                guard let screen = ScreenHelper.screen(for: frame) else { continue }

                result.append(WindowModel(
                    pid: app.processIdentifier,
                    windowElement: window,
                    title: title,
                    frame: frame,
                    screen: screen,
                    appName: app.localizedName ?? ""
                ))
            }
        }

        return result
    }

    static func getFocusedWindow() -> WindowModel? {
        guard isTrusted else {
            log.warning("getFocusedWindow called but not trusted")
            return nil
        }

        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)

        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedValue) == .success else { return nil }
        let window = focusedValue as! AXUIElement

        var positionValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success else { return nil }
        var position = CGPoint.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)

        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success else { return nil }
        var size = CGSize.zero
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)

        var titleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue)
        let title = (titleValue as? String) ?? ""

        let frame = CGRect(origin: position, size: size)
        guard let screen = ScreenHelper.screen(for: frame) else { return nil }

        return WindowModel(
            pid: frontApp.processIdentifier,
            windowElement: window,
            title: title,
            frame: frame,
            screen: screen,
            appName: frontApp.localizedName ?? ""
        )
    }

    static func moveWindow(_ window: WindowModel, to rect: CGRect) {
        log.debug("moveWindow \(window.appName) to \(rect.debugDescription)")
        var position = rect.origin
        var size = rect.size

        let posValue = AXValueCreate(.cgPoint, &position)!
        AXUIElementSetAttributeValue(window.windowElement, kAXPositionAttribute as CFString, posValue)

        let sizeValue = AXValueCreate(.cgSize, &size)!
        AXUIElementSetAttributeValue(window.windowElement, kAXSizeAttribute as CFString, sizeValue)
    }

    static func focusWindow(_ window: WindowModel) {
        log.debug("focusWindow \(window.appName): \(window.title)")
        AXUIElementPerformAction(window.windowElement, kAXRaiseAction as CFString)
        if let app = NSRunningApplication(processIdentifier: window.pid) {
            app.activate()
        }
    }
}
