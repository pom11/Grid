import Testing
import Foundation
@testable import Grid

// ScreenSharingDetector is pure for its decision function so it can be tested
// without a real remote session. (Card t_6061a6ca: no fabricated claims — we
// only test the deterministic decision logic, not the live netstat transport.)

@Suite struct ScreenSharingDetectorTests {

    @Test func noEstablishedConnections_isNotActive() {
        #expect(ScreenSharingDetector.isRemoteSessionActive(establishedVNCPorts: []) == false)
    }

    @Test func establishedConnectionOnDefaultVNCPort_isActive() {
        #expect(ScreenSharingDetector.isRemoteSessionActive(establishedVNCPorts: [5900]) == true)
    }

    @Test func establishedConnectionOnNonDefaultVNCPort_isActive() {
        #expect(ScreenSharingDetector.isRemoteSessionActive(establishedVNCPorts: [5901]) == true)
    }

    @Test func multiplePorts_isActive() {
        #expect(ScreenSharingDetector.isRemoteSessionActive(establishedVNCPorts: [5900, 5901]) == true)
    }
}

// Diagnostic: handleHotKey's combo lookup must return the combo recorded at
// registration, cleared at unregister. Exercises registeredCombos bookkeeping
// used by the new hotkey-trigger log line.
@Suite struct HotKeyDiagnosticsTests {

    @Test func registeredComboRoundTrip() {
        let mgr = HotKeyManager.shared
        let combo = KeyCombo(keyCode: 0x00, modifiers: 0x1000) // control+option+A
        mgr.register(id: 9001, combo: combo, handler: {})
        #expect(mgr.registeredCombos[9001] == combo)
        mgr.unregister(id: 9001)
        #expect(mgr.registeredCombos[9001] == nil)
    }
}
