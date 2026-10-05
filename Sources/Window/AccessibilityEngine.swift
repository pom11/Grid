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

    /// kAXErrorFailure (-25200). Note the header pairs -25200 with kAXErrorFailure and
    /// -25201 with kAXErrorIllegalArgument (AXError.h, MacOSX27.0.sdk) — the report's
    /// "-25200 (kAXErrorIllegalArgument)" conflated the two. A non-resizable window
    /// (styleMask without .resizable — Radio's audio-only panel after applyPanelMode)
    /// rejects AXSize with -25200 here while still accepting AXPosition. Expected, not a
    /// bug; both codes are treated as "this window cannot be resized by AX".
    static let axFailure = AXError(rawValue: -25200)
    static let axIllegalArgument = AXError(rawValue: -25201)

    // MARK: - CGWindowList (z-order + on-screen truth)

    /// One on-screen window as CGWindowList sees it, in front-to-back order.
    struct CGWindowInfo {
        /// 0 = topmost.
        let index: Int
        let pid: pid_t
        let layer: Int
        let bounds: CGRect
    }

    /// On-screen windows in CGWindowList order (index 0 = topmost), own process excluded.
    /// This is the authoritative front-to-back ordering — AX has no z-order concept.
    static func onScreenCGWindows() -> [CGWindowInfo] {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return [] }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        var result: [CGWindowInfo] = []
        result.reserveCapacity(windowList.count)
        var index = 0
        for info in windowList {
            defer { index += 1 }
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID else { continue }
            let layer = info[kCGWindowLayer as String] as? Int ?? Int(Int32.min)
            var bounds = CGRect.zero
            if let raw = info[kCGWindowBounds as String] as? [String: Any] {
                bounds = CGRect(
                    x: raw["X"] as? CGFloat ?? 0,
                    y: raw["Y"] as? CGFloat ?? 0,
                    width: raw["Width"] as? CGFloat ?? 0,
                    height: raw["Height"] as? CGFloat ?? 0
                )
            }
            result.append(CGWindowInfo(index: index, pid: pid, layer: layer, bounds: bounds))
        }
        return result
    }

    /// Screen frames converted from Cocoa (bottom-left of main display, y up) to the
    /// Quartz/AX space that AXPosition and CGWindowList bounds live in — the same
    /// transform `GridRect.toScreenRect` uses to place windows.
    ///
    /// Verified empirically: for a given window, AXPosition+AXSize equals its CGWindowList
    /// bounds to the point, confirming both are Quartz global coordinates.
    static func screenFramesInAXCoordinates() -> [CGRect] {
        let screens = NSScreen.screens
        guard let mainHeight = screens.first?.frame.height else { return [] }
        return screens.map { screen in
            let f = screen.frame
            return CGRect(
                x: f.origin.x,
                y: mainHeight - f.origin.y - f.height,
                width: f.width,
                height: f.height
            )
        }
    }

    /// PIDs of accessory apps that have visible windows, discovered via CGWindowList.
    /// `windows` must come from `onScreenCGWindows()`.
    private static func accessoryPIDs(from windows: [CGWindowInfo]) -> Set<pid_t> {
        var pids = Set<pid_t>()
        for info in windows {
            guard info.layer >= 0, info.layer < 20 else { continue }
            if let app = NSRunningApplication(processIdentifier: info.pid),
               app.activationPolicy == .accessory {
                pids.insert(info.pid)
            }
        }
        return pids
    }

    // MARK: - Resolved windows

    /// A window that survived the eligibility filters, carrying both the live AXUIElement
    /// (needed to move it) and the pure `WindowCandidate` the selection logic reasons over.
    struct ResolvedWindow {
        let candidate: WindowCandidate
        let element: AXUIElement
        let screen: NSScreen

        var windowModel: WindowModel {
            WindowModel(
                pid: candidate.pid,
                windowElement: element,
                title: candidate.title,
                frame: candidate.frame,
                screen: screen,
                appName: candidate.appName
            )
        }
    }

    /// Read one AX window into a pure candidate, or nil when it has no usable geometry.
    /// `zIndex` is filled in by the caller once CGWindowList has been matched.
    private static func candidate(
        for window: AXUIElement,
        pid: pid_t,
        appName: String,
        order: Int,
        id: Int
    ) -> WindowCandidate? {
        var subroleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subroleValue)
        let subrole = (subroleValue as? String) ?? ""

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

        var minimizedValue: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedValue)
        let minimized = (minimizedValue as? Bool) ?? false

        var settable = DarwinBoolean(false)
        let settableErr = AXUIElementIsAttributeSettable(window, kAXPositionAttribute as CFString, &settable)
        if settableErr != .success {
            // Attribute-settability check failed (e.g. the app stopped responding). Assume
            // not settable so a broken window is never chosen as a move target.
            log.debug("IsAttributeSettable failed err=\(settableErr.rawValue) pid=\(pid) title=\(title)")
        }

        return WindowCandidate(
            id: id,
            pid: pid,
            appName: appName,
            title: title,
            subrole: subrole,
            positionSettable: settable.boolValue,
            frame: CGRect(origin: position, size: size),
            isMinimized: minimized,
            zIndex: Int.max,
            order: order
        )
    }

    /// Attach the CGWindowList z-index to each candidate by matching bounds (same Quartz
    /// space, verified to agree to the point). Unmatched windows keep `Int.max` — kept in
    /// the pool but ordered last.
    private static func assignZIndexes(
        _ candidates: [WindowCandidate],
        cgWindows: [CGWindowInfo]
    ) -> [WindowCandidate] {
        var consumed = Set<Int>()
        return candidates.map { candidate in
            let frame = candidate.frame
            let match = cgWindows.first { info in
                guard !consumed.contains(info.index), info.pid == candidate.pid else { return false }
                return abs(info.bounds.origin.x - frame.origin.x) <= 2
                    && abs(info.bounds.origin.y - frame.origin.y) <= 2
                    && abs(info.bounds.width - frame.width) <= 2
                    && abs(info.bounds.height - frame.height) <= 2
            }
            guard let match else { return candidate }
            consumed.insert(match.index)
            var updated = candidate
            updated.zIndex = match.index
            return updated
        }
    }

    /// Eligibility for a window to appear in `listWindows()` — unchanged from v1.1.6 so
    /// the window cycler keeps cycling exactly what it used to.
    private static func isEligibleForListing(candidate: WindowCandidate) -> Bool {
        guard WindowSelection.allowedSubroles.contains(candidate.subrole) else { return false }
        guard !candidate.isMinimized else { return false }
        return true
    }

    /// All eligible windows, resolved once, ordered CGWindowList front-to-back.
    ///
    /// `listWindows()` and `getFocusedWindow()` both build on this single pass so they
    /// cannot disagree about what exists or about what is on top.
    static func resolveWindows(cgWindows: [CGWindowInfo]? = nil) -> [ResolvedWindow] {
        guard isTrusted else {
            GridDiagnostics.report("Grid resolveWindows: accessibility not trusted — no windows")
            return []
        }

        let cgWindows = cgWindows ?? onScreenCGWindows()
        let extraPIDs = accessoryPIDs(from: cgWindows)
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var idCounter = 0
        var resolved: [ResolvedWindow] = []

        for app in NSWorkspace.shared.runningApplications {
            let pid = app.processIdentifier
            guard pid != ownPID else { continue }
            guard app.activationPolicy == .regular || extraPIDs.contains(pid) else { continue }

            let appElement = AXUIElementCreateApplication(pid)
            var windowsValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue) == .success,
                  let windows = windowsValue as? [AXUIElement] else { continue }

            let appName = app.localizedName ?? ""
            // Keep each element paired with its candidate — no index lookups later.
            var pairs: [(element: AXUIElement, candidate: WindowCandidate)] = []
            pairs.reserveCapacity(windows.count)
            for (axIndex, window) in windows.enumerated() {
                guard let base = candidate(for: window, pid: pid, appName: appName,
                                           order: axIndex, id: idCounter) else { continue }
                idCounter += 1
                guard isEligibleForListing(candidate: base) else { continue }
                pairs.append((window, base))
            }

            guard !pairs.isEmpty else { continue }
            let zoned = assignZIndexes(pairs.map(\.candidate), cgWindows: cgWindows)
            for candidate in zoned {
                // Screen resolution kept on the shipped ScreenHelper path so snap targets
                // behave exactly as before.
                guard let screen = ScreenHelper.screen(for: candidate.frame) else { continue }
                let element = pairs.first { $0.candidate.id == candidate.id }!.element
                resolved.append(ResolvedWindow(candidate: candidate, element: element, screen: screen))
            }
        }

        // Re-order the whole pool front-to-back (assignZIndexes was per-app).
        let byID = Dictionary(uniqueKeysWithValues: resolved.map { ($0.candidate.id, $0) })
        return WindowSelection.sortedFrontToBack(resolved.map(\.candidate)).map { byID[$0.id]! }
    }

    // MARK: - Listing

    static func listWindows() -> [WindowModel] {
        resolveWindows().map(\.windowModel)
    }

    // MARK: - Focused window resolution

    /// Resolve the window a hotkey should act on.
    ///
    /// v1.1.6 only ever considered `frontmostApplication`'s AXFocusedWindow, so a Radio
    /// floating panel visible while the menu-bar popover or Notification Center held focus
    /// resolved to the wrong app — or to nothing — and the hotkey appeared dead. Now:
    /// validate that first (unchanged happy path), then fall back through the frontmost
    /// app's own windows, then a validated system-wide focused window, then the topmost
    /// usable window. Every decision and every exit is logged via NSLog so
    /// `log show --predicate process=="Grid"` explains it in the field.
    static func getFocusedWindow() -> WindowModel? {
        guard isTrusted else {
            GridDiagnostics.report("Grid getFocusedWindow: not trusted (accessibility permission missing) — giving up")
            return nil
        }

        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            GridDiagnostics.report("Grid getFocusedWindow: no frontmost application — giving up")
            return nil
        }
        let frontPID = frontApp.processIdentifier

        // Pool = every eligible window (same read path listWindows() uses), ordered
        // front-to-back. The two focused-window candidates get their own read because they
        // may be windows the pool excludes — e.g. the NSPopover window, whose empty subrole
        // is exactly what makes it invalid.
        let cgWindows = onScreenCGWindows()
        let pool = resolveWindows(cgWindows: cgWindows)
        let screenFrames = screenFramesInAXCoordinates()

        var focusedElementCache: [Int: AXUIElement] = [:]
        func focusedCandidate(_ element: AXUIElement, fallbackPID: pid_t, id: Int) -> WindowCandidate? {
            focusedElementCache[id] = element
            return candidateForElement(element, fallbackPID: fallbackPID, order: Int.min,
                                       id: id, cgWindows: cgWindows)
        }

        let frontmostFocused = focusedWindowElement(of: frontPID).flatMap {
            focusedCandidate($0, fallbackPID: frontPID, id: Self.frontmostFocusedID)
        }
        let systemWideFocused = systemWideFocusedWindowElement().flatMap {
            focusedCandidate($0, fallbackPID: 0, id: Self.systemWideFocusedID)
        }
        let frontmostAppWindows = pool.filter { $0.candidate.pid == frontPID }.map(\.candidate)
        let allWindows = pool.map(\.candidate)

        guard let choice = WindowSelection.select(
            frontmostFocused: frontmostFocused,
            frontmostPID: frontPID,
            frontmostAppWindows: frontmostAppWindows,
            systemWideFocused: systemWideFocused,
            allWindows: allWindows,
            screenFrames: screenFrames
        ) else {
            GridDiagnostics.report("Grid getFocusedWindow: no usable window (frontmost=\(frontApp.localizedName ?? "?") pid=\(frontPID), pool=\(pool.count)) — giving up")
            return nil
        }

        // The winner must be a window we can actually move: pooled windows carry their
        // element from the same pass; the two focused candidates were cached on read.
        let windowElement: AXUIElement
        if let pooled = pool.first(where: { $0.candidate.id == choice.candidate.id }) {
            windowElement = pooled.element
        } else if let cached = focusedElementCache[choice.candidate.id] {
            windowElement = cached
        } else {
            GridDiagnostics.report("Grid getFocusedWindow: selected \(choice.strategy.rawValue) window has no AX element — giving up")
            return nil
        }

        let frame = choice.candidate.frame
        let screen = ScreenHelper.screen(for: frame) ?? NSScreen.main
        guard let screen else {
            GridDiagnostics.report("Grid getFocusedWindow: no screen for frame \(NSStringFromRect(frame)) — giving up")
            return nil
        }

        GridDiagnostics.note("Grid getFocusedWindow: \(choice.candidate.appName.isEmpty ? "pid \(choice.candidate.pid)" : choice.candidate.appName) via \(choice.strategy.rawValue) (frontmost=\(frontApp.localizedName ?? "?") pid=\(frontPID), pool=\(pool.count), title='\(choice.candidate.title)', subrole=\(choice.candidate.subrole), frame=\(NSStringFromRect(frame)))")

        return WindowModel(
            pid: choice.candidate.pid,
            windowElement: windowElement,
            title: choice.candidate.title,
            frame: frame,
            screen: screen,
            appName: choice.candidate.appName
        )
    }

    /// The app's AXFocusedWindow, if it reports one.
    private static func focusedWindowElement(of pid: pid_t) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(pid)
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedValue) == .success,
              let focusedValue, CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            return nil
        }
        return (focusedValue as! AXUIElement)
    }

    /// The system-wide focused element's window — kept for compatibility with the v1.1.6
    /// fallback, but demoted behind the frontmost app's own windows: on macOS 27 it
    /// frequently fails outright (observed live: kAXErrorCannotComplete, -25204) or
    /// returns a non-window element.
    private static func systemWideFocusedWindowElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success else {
            return nil
        }
        let element = focusedValue as! AXUIElement
        var windowValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &windowValue) == .success,
           let windowValue, CFGetTypeID(windowValue) == AXUIElementGetTypeID() {
            return (windowValue as! AXUIElement)
        }
        var roleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        return (roleValue as? String) == kAXWindowRole ? element : nil
    }

    /// Negative candidate ids reserved for the two ad-hoc focused-window reads, so they
    /// never collide with pooled windows (ids are assigned from 0 upward).
    static let frontmostFocusedID = -1
    static let systemWideFocusedID = -2

    /// Build a candidate for an element obtained outside `resolveWindows()` (the focused
    /// window of the frontmost app, or the system-wide focused window).
    private static func candidateForElement(
        _ element: AXUIElement,
        fallbackPID: pid_t,
        order: Int,
        id: Int,
        cgWindows: [CGWindowInfo]? = nil
    ) -> WindowCandidate? {
        var pid: pid_t = fallbackPID
        AXUIElementGetPid(element, &pid)
        let appName = NSRunningApplication(processIdentifier: pid)?.localizedName ?? ""
        guard var candidate = candidate(for: element, pid: pid, appName: appName,
                                       order: order, id: id) else { return nil }
        let z = assignZIndexes([candidate], cgWindows: cgWindows ?? onScreenCGWindows())
        if let matched = z.first, matched.zIndex != Int.max { candidate.zIndex = matched.zIndex }
        return candidate
    }

    // MARK: - Moving

    /// Move (and resize) a window, logging what the AX API actually answered.
    ///
    /// v1.1.6 discarded both return codes, so a rejected write was indistinguishable from
    /// a successful one — the "nothing happens" report left no trace. Write order is
    /// unchanged (position then size) so regular-app snapping behaves exactly as before;
    /// what is added is the return codes, an expected-rejection note for non-resizable
    /// windows, and a post-write readback so field logs show where the window ended up.
    static func moveWindow(_ window: WindowModel, to rect: CGRect) {
        let element = window.windowElement
        let before = currentFrame(of: element)

        var position = rect.origin
        guard let posValue = AXValueCreate(.cgPoint, &position) else {
            GridDiagnostics.report("Grid moveWindow: could not encode position \(NSStringFromRect(rect)) for \(window.appName) — aborting")
            return
        }
        let posErr = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, posValue)

        // Skip the size write when the window is already the right size (within 2pt).
        // Radio's audio-only panel drops .resizable from its styleMask in audio-only mode,
        // so every size write on it is rejected; skipping when nothing changes keeps the
        // field log free of noise that would bury real failures.
        var sizeWriteSkipped = false
        var sizeErr = AXError.success

        if let current = currentSize(of: element),
           abs(current.width - rect.size.width) <= 2, abs(current.height - rect.size.height) <= 2 {
            sizeWriteSkipped = true
        } else {
            var size = rect.size
            if let sizeValue = AXValueCreate(.cgSize, &size) {
                sizeErr = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
            } else {
                sizeErr = .cannotComplete
            }
        }

        let sizeNote: String
        if sizeWriteSkipped {
            sizeNote = "size unchanged (within 2pt), write skipped"
        } else if sizeErr == axFailure || sizeErr == axIllegalArgument {
            sizeNote = "size rejected err=\(sizeErr.rawValue) (window not resizable — expected for panel windows)"
        } else {
            sizeNote = "size err=\(sizeErr.rawValue)"
        }

        let readback = currentFrame(of: element)
        let line = "Grid moveWindow: '\(window.title.isEmpty ? window.appName : window.title)' (pid \(window.pid)) "
            + "\(before.map { NSStringFromRect($0) } ?? "unknown") -> \(NSStringFromRect(rect)) "
            + "| setPos err=\(posErr.rawValue), \(sizeNote) "
            + "| readback=\(readback.map { NSStringFromRect($0) } ?? "unavailable")"
        if posErr != .success {
            // A failed position write is exactly the "nothing happened" the user reports.
            GridDiagnostics.report(line)
            log.error("moveWindow position set failed err=\(posErr.rawValue) app=\(window.appName)")
        } else {
            GridDiagnostics.note(line)
        }
    }

    private static func currentSize(of element: AXUIElement) -> CGSize? {
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return size
    }

    private static func currentFrame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }

    static func focusWindow(_ window: WindowModel) {
        log.debug("focusWindow \(window.appName): \(window.title)")
        AXUIElementPerformAction(window.windowElement, kAXRaiseAction as CFString)
        if let app = NSRunningApplication(processIdentifier: window.pid) {
            app.activate()
        }
    }
}
