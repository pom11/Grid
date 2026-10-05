import Testing
import Foundation
import CoreGraphics
@testable import Grid

// WindowSelection is pure (no AppKit, no AX) — these tests are the guarantee that the
// focused-window chain fixes Radio's panels without changing regular-app behaviour.

private let mainScreen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
private let secondScreen = CGRect(x: 1920, y: 0, width: 2560, height: 1440)
private let screens = [mainScreen, secondScreen]

private func candidate(
    id: Int,
    pid: pid_t = 100,
    app: String = "App",
    title: String = "win",
    subrole: String = "AXStandardWindow",
    settable: Bool = true,
    frame: CGRect = CGRect(x: 100, y: 100, width: 800, height: 600),
    minimized: Bool = false,
    z: Int = 0
) -> WindowCandidate {
    WindowCandidate(
        id: id, pid: pid, appName: app, title: title, subrole: subrole,
        positionSettable: settable, frame: frame, isMinimized: minimized,
        zIndex: z, order: id
    )
}

// MARK: - isUsable

@Test func usableStandardWindow() {
    #expect(WindowSelection.isUsable(candidate(id: 0), screenFrames: screens))
}

@Test func usableFloatingWindowAndSystemDialog() {
    #expect(WindowSelection.isUsable(candidate(id: 0, subrole: "AXFloatingWindow"), screenFrames: screens))
    // Radio's audio-only panel reports AXSystemDialog — it MUST stay usable.
    #expect(WindowSelection.isUsable(candidate(id: 0, subrole: "AXSystemDialog"), screenFrames: screens))
}

@Test func popoverWindowWithEmptySubroleIsRejected() {
    // The live reproduction: Radio's menu-bar popover is the frontmost app's focused window
    // and reports an EMPTY subrole. It must never be picked as a snap target.
    #expect(!WindowSelection.isUsable(candidate(id: 0, subrole: ""), screenFrames: screens))
}

@Test func unknownSubroleIsRejected() {
    #expect(!WindowSelection.isUsable(candidate(id: 0, subrole: "AXSheet"), screenFrames: screens))
    #expect(!WindowSelection.isUsable(candidate(id: 0, subrole: "AXPopover"), screenFrames: screens))
}

@Test func nonSettablePositionWindowIsRejected() {
    // Notification Center's dialog reported AXPosition as not settable on this host.
    #expect(!WindowSelection.isUsable(candidate(id: 0, settable: false), screenFrames: screens))
}

@Test func minimizedWindowIsRejected() {
    #expect(!WindowSelection.isUsable(candidate(id: 0, minimized: true), screenFrames: screens))
}

@Test func degenerateSizeIsRejected() {
    #expect(!WindowSelection.isUsable(
        candidate(id: 0, frame: CGRect(x: 10, y: 10, width: 0, height: 100)), screenFrames: screens))
    #expect(!WindowSelection.isUsable(
        candidate(id: 0, frame: CGRect(x: 10, y: 10, width: 100, height: 0)), screenFrames: screens))
}

@Test func offScreenWindowIsRejected() {
    // Far away from both displays.
    let far = CGRect(x: 9000, y: 9000, width: 400, height: 300)
    #expect(!WindowSelection.isUsable(candidate(id: 0, frame: far), screenFrames: screens))
}

@Test func windowPartiallyOffScreenIsAccepted() {
    // A window straddling the display edge is still a legitimate snap target.
    let straddle = CGRect(x: 1900, y: 100, width: 200, height: 200)
    #expect(WindowSelection.isUsable(candidate(id: 0, frame: straddle), screenFrames: screens))
}

@Test func windowOnSecondDisplayIsAccepted() {
    let onSecond = CGRect(x: 2000, y: 200, width: 800, height: 600)
    #expect(WindowSelection.isUsable(candidate(id: 0, frame: onSecond), screenFrames: screens))
}

// MARK: - z-order

@Test func sortedFrontToBackUsesZIndexNotInsertionOrder() {
    let windows = [
        candidate(id: 0, app: "back", z: 7),
        candidate(id: 1, app: "top", z: 1),
        candidate(id: 2, app: "middle", z: 4),
    ]
    let sorted = WindowSelection.sortedFrontToBack(windows)
    #expect(sorted.map(\.appName) == ["top", "middle", "back"])
}

@Test func unmatchedWindowsSortLastAndStably() {
    let windows = [
        candidate(id: 0, app: "unmatched1", z: Int.max),
        candidate(id: 1, app: "matched", z: 3),
        candidate(id: 2, app: "unmatched2", z: Int.max),
    ]
    let sorted = WindowSelection.sortedFrontToBack(windows)
    #expect(sorted[0].appName == "matched")
    #expect(sorted[1].appName == "unmatched1")
    #expect(sorted[2].appName == "unmatched2")
}

// MARK: - select(): the regression guarantee

@Test func validFrontmostFocusedWindowWinsOverEverything() {
    // Safari frontmost: pressing a zone hotkey must keep snapping Safari, exactly as v1.1.6.
    let safari = candidate(id: 5, pid: 400, app: "Safari", title: "example.com", z: 2)
    let radioPanel = candidate(id: 6, pid: 500, app: "Radio", subrole: "AXSystemDialog", z: 0)
    let choice = WindowSelection.select(
        frontmostFocused: safari,
        frontmostPID: 400,
        frontmostAppWindows: [safari],
        systemWideFocused: radioPanel,
        allWindows: [radioPanel, safari],
        screenFrames: screens
    )
    #expect(choice?.candidate.appName == "Safari")
    #expect(choice?.strategy == .frontmostFocused)
}

@Test func frontmostAppOwnWindowUsedWhenFocusedWindowIsPopover() {
    // THE Radio case: Radio is frontmost, its focused window is the menu-bar popover
    // (empty subrole), and its floating audio-only panel is visible. Must resolve to the
    // panel via the frontmost app's own windows — before any global search.
    let popover = candidate(id: 0, pid: 500, app: "Radio", subrole: "", z: 0)
    let panel = candidate(id: 1, pid: 500, app: "Radio", title: "Player",
                          subrole: "AXSystemDialog", z: 1)
    let otherApps = [
        candidate(id: 2, pid: 600, app: "Finder", z: 3),
        candidate(id: 3, pid: 700, app: "iTerm2", z: 2),
    ]
    let choice = WindowSelection.select(
        frontmostFocused: popover,
        frontmostPID: 500,
        frontmostAppWindows: [panel] + otherApps.filter { $0.pid == 500 },
        systemWideFocused: nil,
        allWindows: [popover, panel] + otherApps,
        screenFrames: screens
    )
    #expect(choice?.candidate.title == "Player")
    #expect(choice?.strategy == .frontmostAppWindows)
}

@Test func frontmostAppOwnWindowBeatsGlobalTopmostWindow() {
    // Ordering requirement: a lower-z window owned by the frontmost app must still win over
    // a higher-z window owned by some other app.
    let focusedJunk = candidate(id: 0, pid: 500, app: "Radio", subrole: "", z: 0)
    let ownPanel = candidate(id: 1, pid: 500, app: "Radio", subrole: "AXSystemDialog", z: 9)
    let otherTopWindow = candidate(id: 2, pid: 600, app: "Safari", z: 1)
    let choice = WindowSelection.select(
        frontmostFocused: focusedJunk,
        frontmostPID: 500,
        frontmostAppWindows: [ownPanel],
        systemWideFocused: nil,
        allWindows: [otherTopWindow, ownPanel],
        screenFrames: screens
    )
    #expect(choice?.candidate.appName == "Radio")
    #expect(choice?.strategy == .frontmostAppWindows)
}

@Test func skipsUnusableOwnWindowsToFrontmostAppNextUsable() {
    let focusedJunk = candidate(id: 0, pid: 500, app: "Radio", subrole: "", z: 0)
    let minimizedOwn = candidate(id: 1, pid: 500, app: "Radio", minimized: true, z: 1)
    let unmovableOwn = candidate(id: 2, pid: 500, app: "Radio", settable: false, z: 2)
    let goodOwn = candidate(id: 3, pid: 500, app: "Radio", title: "Player",
                            subrole: "AXSystemDialog", z: 5)
    let choice = WindowSelection.select(
        frontmostFocused: focusedJunk,
        frontmostPID: 500,
        frontmostAppWindows: [minimizedOwn, unmovableOwn, goodOwn],
        systemWideFocused: nil,
        allWindows: [focusedJunk, minimizedOwn, unmovableOwn, goodOwn],
        screenFrames: screens
    )
    #expect(choice?.candidate.title == "Player")
    #expect(choice?.strategy == .frontmostAppWindows)
}

@Test func fallsBackToTopmostWindowWhenFrontmostAppHasNothingUsable() {
    // Live case: Notification Center / Finder desktop frontmost with no usable window,
    // Radio's panel visible underneath. Global topmost usable window must win.
    let junk = candidate(id: 0, pid: 2392, app: "NotificationCenter", subrole: "", z: 0)
    let radioPanel = candidate(id: 1, pid: 500, app: "Radio", title: "Player",
                               subrole: "AXSystemDialog", z: 4)
    let choice = WindowSelection.select(
        frontmostFocused: junk,
        frontmostPID: 2392,
        frontmostAppWindows: [],
        systemWideFocused: nil,
        allWindows: [junk, radioPanel],
        screenFrames: screens
    )
    #expect(choice?.candidate.title == "Player")
    #expect(choice?.strategy == .topmostWindow)
}

@Test func topmostFallbackPicksHighestZUsableWindow() {
    let junk = candidate(id: 0, pid: 2392, app: "NotificationCenter", subrole: "", z: 0)
    let safari = candidate(id: 1, pid: 600, app: "Safari", title: "Safari", z: 2)
    let radioPanel = candidate(id: 2, pid: 500, app: "Radio", title: "Player",
                               subrole: "AXSystemDialog", z: 1)
    let choice = WindowSelection.select(
        frontmostFocused: junk,
        frontmostPID: 2392,
        frontmostAppWindows: [],
        systemWideFocused: nil,
        allWindows: [junk, safari, radioPanel],
        screenFrames: screens
    )
    #expect(choice?.candidate.title == "Safari")
    #expect(choice?.strategy == .topmostWindow)
}

@Test func systemWideFocusedUsedOnlyAfterFrontmostAppsOwnWindows() {
    // System-wide focused is a global search: it must rank behind the frontmost app's own
    // windows but ahead of the plain topmost-window sweep.
    let focusedJunk = candidate(id: 0, pid: 500, app: "Radio", subrole: "", z: 0)
    let ownPanel = candidate(id: 1, pid: 500, app: "Radio", subrole: "AXSystemDialog", z: 8)
    let systemWindow = candidate(id: 2, pid: 700, app: "Mail", z: 1)
    let choice = WindowSelection.select(
        frontmostFocused: focusedJunk,
        frontmostPID: 500,
        frontmostAppWindows: [ownPanel],
        systemWideFocused: systemWindow,
        allWindows: [focusedJunk, ownPanel, systemWindow],
        screenFrames: screens
    )
    #expect(choice?.candidate.appName == "Radio")

    // With no own usable window, the validated system-wide window wins over the sweep.
    let choice2 = WindowSelection.select(
        frontmostFocused: focusedJunk,
        frontmostPID: 500,
        frontmostAppWindows: [],
        systemWideFocused: systemWindow,
        allWindows: [focusedJunk, candidate(id: 3, pid: 800, app: "Notes", z: 0)],
        screenFrames: screens
    )
    #expect(choice2?.candidate.appName == "Mail")
    #expect(choice2?.strategy == .systemWideFocused)
}

@Test func unusableSystemWideFocusedWindowIsIgnored() {
    let focusedJunk = candidate(id: 0, pid: 500, app: "Radio", subrole: "", z: 0)
    let systemJunk = candidate(id: 1, pid: 900, app: "Something", subrole: "", z: 1)
    let sweep = candidate(id: 2, pid: 600, app: "Safari", z: 2)
    let choice = WindowSelection.select(
        frontmostFocused: focusedJunk,
        frontmostPID: 500,
        frontmostAppWindows: [],
        systemWideFocused: systemJunk,
        allWindows: [focusedJunk, systemJunk, sweep],
        screenFrames: screens
    )
    #expect(choice?.candidate.appName == "Safari")
    #expect(choice?.strategy == .topmostWindow)
}

@Test func selectReturnsNilWhenNothingIsUsable() {
    let all = [
        candidate(id: 0, app: "A", subrole: "", z: 0),
        candidate(id: 1, app: "B", settable: false, z: 1),
        candidate(id: 2, app: "C", frame: CGRect(x: 9000, y: 9000, width: 10, height: 10), z: 2),
    ]
    let choice = WindowSelection.select(
        frontmostFocused: all[0],
        frontmostPID: 100,
        frontmostAppWindows: [all[1]],
        systemWideFocused: all[2],
        allWindows: all,
        screenFrames: screens
    )
    #expect(choice == nil)
}

@Test func selectHandlesAllNilInputs() {
    let choice = WindowSelection.select(
        frontmostFocused: nil,
        frontmostPID: 100,
        frontmostAppWindows: [],
        systemWideFocused: nil,
        allWindows: [],
        screenFrames: screens
    )
    #expect(choice == nil)
}

@Test func selectRejectsUsableLookingWindowThatIsOffScreen() {
    // Even the frontmost focused window must intersect a screen, otherwise a snap would move
    // a window Grid cannot see.
    let offScreen = candidate(id: 0, pid: 400, app: "Ghost", subrole: "AXStandardWindow",
                              frame: CGRect(x: -5000, y: -5000, width: 800, height: 600))
    let visible = candidate(id: 1, pid: 500, app: "Radio", title: "Player",
                            subrole: "AXSystemDialog", z: 3)
    let choice = WindowSelection.select(
        frontmostFocused: offScreen,
        frontmostPID: 400,
        frontmostAppWindows: [offScreen],
        systemWideFocused: nil,
        allWindows: [offScreen, visible],
        screenFrames: screens
    )
    #expect(choice?.candidate.title == "Player")
    #expect(choice?.strategy == .topmostWindow)
}

@Test func candidatesAreEqualByIdentityNotFrame() {
    // Two different windows that happen to share a frame must not collapse.
    let a = candidate(id: 1, pid: 100, app: "A", z: 0)
    let b = candidate(id: 2, pid: 200, app: "B", z: 0)
    #expect(a != b)
    #expect(a == candidate(id: 1, pid: 100, app: "A Renamed", title: "other", z: 9))
}
