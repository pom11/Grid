import Foundation
import os.log

/// Field diagnostics channel for Grid.
///
/// Why this exists (measured on macOS 27.0.1 — task t_b4cd532f): the field question
/// "why did my hotkey do nothing?" is answered with
///     log show --predicate 'process == "Grid"'
/// and on this OS the obvious choices are invisible to exactly that query:
///
///   NSLog(...)              -> stored at debug level AND <private>: needs --info --debug
///                              plus a privacy override, so the operator sees ZERO lines
///                              even when the code ran (at least part of why v1.1.4/1.1.6
///                              produced "no WindowSnapper lines in 24h of log show" while
///                              the string was verifiably in the binary)
///   Logger.debug / .info    -> filtered out unless --info/--debug are passed
///   Logger.log / .warning /
///   .error                  -> VISIBLE, values unredacted
///
/// Interpolated values in Swift's Logger default to <private>, so the message is passed
/// with `privacy: .public`. NSLog is still called (harmless, and it shows in Console.app
/// and when Grid is run from a terminal).
enum GridDiagnostics {
    private static let logger = Logger(subsystem: "ro.pom.grid", category: "diagnostics")

    /// Something the user needs to be able to find when a hotkey misbehaved: an early
    /// exit, a rejected AX write, a failed registration. Always visible.
    static func report(_ message: String) {
        logger.warning("\(message, privacy: .public)")
        NSLog("%@", message)
    }

    /// Informational trace (which window was chosen, where it landed). Visible to the
    /// plain `log show`, but kept one level below `report` so a hotkey press does not
    /// shout.
    static func note(_ message: String) {
        logger.log("\(message, privacy: .public)")
        NSLog("%@", message)
    }
}
