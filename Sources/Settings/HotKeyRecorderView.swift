import SwiftUI
import Carbon.HIToolbox
import os.log

private let log = Logger(subsystem: "ro.pom.grid", category: "hotkey-recorder")

struct HotKeyRecorderView: View {
    let label: String
    @Binding var combo: KeyCombo?
    @State private var isRecording = false
    @State private var eventMonitor: Any?

    var body: some View {
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
                }
                .buttonStyle(.borderless)
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
            log.debug("Recorded hotkey: \(newCombo.displayString)")
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
