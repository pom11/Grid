import Foundation
import os.log

// MARK: - ScreenSharingDetector
//
// Detects whether a remote session (Apple Screen Sharing / VNC) is actively
// controlling this machine. This is relevant to Grid's global hotkeys: when a
// remote session owns the keyboard input, Carbon RegisterEventHotKey handlers
// on the local application event target typically stop receiving
// kEventHotKeyPressed (documented platform behavior — see FINDINGS file), so
// Grid hotkeys don't fire locally until the remote session disconnects.

private let log = Logger(subsystem: "ro.pom.grid", category: "screensharing")

enum ScreenSharingDetector {

    /// The VNC/rfb server port macOS Screen Sharing listens on by default.
    static let defaultVNCPort: UInt16 = 5900

    /// Pure decision helper, isolated so it can be unit-tested without needing
    /// a real remote session. A session is "active" when at least one local
    /// VNC port has an ESTABLISHED inbound connection — i.e. screensharing is
    /// enabled AND a remote client is actually connected (not merely enabled).
    ///
    /// - Parameter establishedVNCPorts: set of local TCP ports that currently
    ///   have an ESTABLISHED inbound connection for a remote session.
    static func isRemoteSessionActive(establishedVNCPorts: Set<UInt16>) -> Bool {
        !establishedVNCPorts.isEmpty
    }

    /// Live check: query the local TCP table for ESTABLISHED inbound
    /// connections on the VNC listening ports, then decide.
    static func detectActiveRemoteSession() -> Bool {
        let ports = establishedVNCPortsNow()
        if isRemoteSessionActive(establishedVNCPorts: ports) {
            log.info("Screen Sharing / VNC remote session active: established on port(s) \(ports.sorted())")
            return true
        }
        return false
    }

    /// Query /usr/sbin/netstat for ESTABLISHED inbound connections on the VNC
    /// listening ports. Returns the set of local ports with such a connection.
    ///
    /// Apple Screen Sharing (screensharingd) accepts connections on TCP 5900.
    /// A connected remote viewer appears as an ESTABLISHED socket whose local
    /// address ends in the VNC port.
    static func establishedVNCPortsNow() -> Set<UInt16> {
        let candidatePorts: Set<UInt16> = [defaultVNCPort]

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/netstat")
        proc.arguments = ["-an"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
        } catch {
            log.error("netstat failed to launch: \(error.localizedDescription)")
            return []
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return [] }

        var result: Set<UInt16> = []
        for line in text.split(separator: "\n") {
            // netstat -an TCP lines look like:
            //   tcp4  0  0  *.5900  *.*  LISTEN
            //   tcp4  0 42  100.64.0.1.5900  dest.example.51000  ESTABLISHED
            // We care about ESTABLISHED lines whose local address ends in a
            // candidate VNC port.
            guard line.contains("ESTABLISHED") else { continue }
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 5 else { continue }
            // Local address is fields[3], e.g. "*.5900" or "100.64.0.1.5900".
            // The port is the last dot-separated component.
            let localAddr = String(fields[3])
            guard let lastDot = localAddr.lastIndex(of: ".") else { continue }
            guard let port = UInt16(localAddr[localAddr.index(after: lastDot)...]) else { continue }
            if candidatePorts.contains(port) {
                result.insert(port)
            }
        }
        return result
    }
}
