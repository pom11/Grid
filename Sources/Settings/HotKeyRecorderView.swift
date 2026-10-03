import SwiftUI
import Carbon.HIToolbox
import os.log

private let log = Logger(subsystem: "ro.pom.grid", category: "hotkey-recorder")

struct HotKeyRecorderView: View {
    let label: String
    @Binding var combo: KeyCombo?
    /// The slot/zone this recorder assigns, so the collision scan can exclude
    /// the combo's own current assignment (re-recording the same combo onto the
    /// same slot/zone is a no-op, not a collision).
    var slot: Slot? = nil
    @State private var isRecording = false
    @State private var eventMonitor: Any?
    @State private var collisionTarget: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if !label.isEmpty {
                    Text(label)
                        .frame(width: 180, alignment: .leading)
                }

                Button(action: { toggleRecording() }) {
                    Text(isRecording ? "Press keys..." : (combo?.displayString ?? "Click to set"))
                        .frame(minWidth: 120)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .overlay(
                    isRecording ? RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor, lineWidth: 2) : nil
                )

                if combo != nil {
                    Button("Clear") {
                        combo = nil
                        collisionTarget = nil
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.red)
                }
            }

            if let collision = collisionTarget {
                Label {
                    Text("Shortcut already assigned to \(collision). Choose a different combination.")
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .font(.caption)
                .foregroundColor(.red)
            }
        }
        .onDisappear { stopRecording() }
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        log.debug("Started recording hotkey")
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            let mods = KeyCombo.carbonModifiers(from: event.modifierFlags)
            // Escape cancels recording
            if event.keyCode == 53 {
                log.debug("Recording cancelled (Escape)")
                stopRecording()
                return nil
            }
            guard mods != 0 else { return nil }
            let newCombo = KeyCombo(keyCode: UInt32(event.keyCode), modifiers: mods)

            // Refuse combos already in use by another slot/zone instead of
            // silently failing to register (or worse, shadowing the other one).
            if let collision = HotKeyManager.shared.findCollision(newCombo, excludingId: slot?.rawValue) {
                collisionTarget = collision
                log.warning("Hotkey \\(newCombo.displayString) collides with \\(collision); refusing assignment")
                stopRecording()
                return nil
            }

            log.debug("Recorded hotkey: \\(newCombo.displayString)")
            collisionTarget = nil
            combo = newCombo
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}

extension KeyCombo {
    /// Convert NSEvent.ModifierFlags to Carbon modifiers
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        return result
    }
}
