import CoreGraphics
import Foundation

/// A window described by plain values, so the "which window should Grid act on?" decision
/// can be unit-tested without a GUI, an AX connection, or a running app.
///
/// `AccessibilityEngine` produces these from live AXUIElements (see `ResolvedWindow`),
/// and `WindowSelection.select` turns a bundle of them into the single target window.
struct WindowCandidate: Equatable {
    /// Stable identity of the backing AXUIElement within one resolution pass.
    var id: Int
    var pid: pid_t
    var appName: String
    var title: String
    /// AX subrole, e.g. "AXStandardWindow". NSPopover windows report an EMPTY subrole.
    var subrole: String
    /// Whether AX reported AXPosition as settable (Notification Center dialogs are not).
    var positionSettable: Bool
    /// AX frame (top-left origin, AppKit/global coordinates).
    var frame: CGRect
    var isMinimized: Bool
    /// 0 = topmost in CGWindowList front-to-back order; `Int.max` when this window could
    /// not be matched to an on-screen CGWindow (kept, sorted last).
    var zIndex: Int
    /// Discovery index — tiebreaker so sorting is deterministic.
    var order: Int

    static func == (lhs: WindowCandidate, rhs: WindowCandidate) -> Bool {
        lhs.id == rhs.id && lhs.pid == rhs.pid
    }
}

enum SelectionStrategy: String, Equatable {
    /// Frontmost app's AXFocusedWindow was valid — today's behaviour, the common case.
    case frontmostFocused
    /// Frontmost app's own usable windows, front-to-back. Resolves Radio's panel while its
    /// menu-bar popover holds focus.
    case frontmostAppWindows
    /// System-wide focused element's window, validated.
    case systemWideFocused
    /// Topmost usable window across all apps.
    case topmostWindow
}

/// The focused-window decision, expressed as pure functions.
///
/// Ordering is deliberately conservative: pressing a snap hotkey while Safari is frontmost
/// must keep snapping Safari. Only when the frontmost app's focused window is unusable
/// (empty subrole = NSPopover, un-settable position = Notification Center dialog, off
/// screen) do we widen the search, and the frontmost app's OWN windows are searched before
/// any global search.
enum WindowSelection {
    /// Subroles Grid is willing to move.
    static let allowedSubroles: Set<String> = [
        "AXStandardWindow", "AXFloatingWindow", "AXSystemDialog",
    ]

    /// A window is usable when it is a real movable window kind (non-empty, allowed
    /// subrole — NSPopover reports an empty subrole and is therefore rejected), its
    /// position can actually be set, it is not minimized, it has non-degenerate size, and
    /// it intersects at least one screen.
    static func isUsable(_ window: WindowCandidate, screenFrames: [CGRect]) -> Bool {
        guard !window.subrole.isEmpty, allowedSubroles.contains(window.subrole) else { return false }
        guard window.positionSettable else { return false }
        guard !window.isMinimized else { return false }
        guard window.frame.width > 0, window.frame.height > 0 else { return false }
        return screenFrames.contains { $0.intersects(window.frame) }
    }

    /// Front-to-back order: CGWindowList z-order, discovery index as deterministic tiebreak.
    static func sortedFrontToBack(_ windows: [WindowCandidate]) -> [WindowCandidate] {
        windows.sorted { a, b in
            if a.zIndex != b.zIndex { return a.zIndex < b.zIndex }
            return a.order < b.order
        }
    }

    /// Resolve the window a hotkey should act on.
    ///
    /// - Parameters:
    ///   - frontmostFocused: the frontmost app's AXFocusedWindow, if any. NOT pre-validated.
    ///   - frontmostPID: pid of the frontmost application.
    ///   - frontmostAppWindows: all usable windows belonging to `frontmostPID`,
    ///     already ordered front-to-back (AX reports its window list in that order).
    ///   - systemWideFocused: the system-wide focused element's window, if any.
    ///   - allWindows: every usable window across eligible apps, ordered front-to-back.
    /// Returns the winner and which strategy produced it (the caller logs the strategy, so
    /// `log show --predicate process=="Grid"` explains a move in the field).
    static func select(
        frontmostFocused: WindowCandidate?,
        frontmostPID: pid_t,
        frontmostAppWindows: [WindowCandidate],
        systemWideFocused: WindowCandidate?,
        allWindows: [WindowCandidate],
        screenFrames: [CGRect]
    ) -> (candidate: WindowCandidate, strategy: SelectionStrategy)? {
        // 1. Today's behaviour: a valid focused window in the frontmost app.
        if let focused = frontmostFocused, isUsable(focused, screenFrames: screenFrames) {
            return (focused, .frontmostFocused)
        }
        // 2. The frontmost app's own usable windows, front-to-back. Radio's audio-only panel
        //    lives here while the menu-bar popover (empty subrole) holds focus.
        if let own = frontmostAppWindows.first(where: { isUsable($0, screenFrames: screenFrames) }) {
            return (own, .frontmostAppWindows)
        }
        // 3. System-wide focused window, validated the same way. (A global search, so it
        //    comes after the frontmost app's own windows; in practice it is often
        //    unavailable — kAXErrorAPIDisabled — which is why it is not first.)
        if let system = systemWideFocused, isUsable(system, screenFrames: screenFrames) {
            return (system, .systemWideFocused)
        }
        // 4. Topmost usable window anywhere.
        if let top = allWindows.first(where: { isUsable($0, screenFrames: screenFrames) }) {
            return (top, .topmostWindow)
        }
        return nil
    }
}
