import SwiftUI

struct HotkeysTab: View {
    @State private var focusNext: KeyCombo?
    @State private var focusPrev: KeyCombo?
    @State private var moveNext: KeyCombo?
    @State private var movePrev: KeyCombo?
    var onHotkeysChanged: (() -> Void)?

    var body: some View {
        Form {
            if remoteSessionActive {
                Label {
                    Text("Grid's global hotkeys are temporarily unavailable — macOS routes global hotkeys to the remote computer while Screen Sharing / VNC controls this Mac. They resume automatically once the remote session disconnects.")
                        .font(.callout)
                } icon: {
                    Image(systemName: "warningtriangle")
                        .foregroundStyle(.orange)
                }
                .padding(8)
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }

            Section("Focus Cycling") {
                HotKeyRecorderView(label: "Focus next window", combo: $focusNext, slot: .focusNext)
                    .onChange(of: focusNext) { _, val in save(.focusNext, val) }
                HotKeyRecorderView(label: "Focus previous window", combo: $focusPrev, slot: .focusPrevious)
                    .onChange(of: focusPrev) { _, val in save(.focusPrevious, val) }
            }

            Section("Move Between Displays") {
                HotKeyRecorderView(label: "Move to next display", combo: $moveNext, slot: .moveNextDisplay)
                    .onChange(of: moveNext) { _, val in save(.moveNextDisplay, val) }
                HotKeyRecorderView(label: "Move to previous display", combo: $movePrev, slot: .movePrevDisplay)
                    .onChange(of: movePrev) { _, val in save(.movePrevDisplay, val) }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { loadAll() }
        .task { refreshRemoteSessionStatus() }
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
            refreshRemoteSessionStatus()
        }
    }

    @State private var remoteSessionActive = false

    private func refreshRemoteSessionStatus() {
        // netstat is a subprocess; don't block the main thread on it.
        Task.detached(priority: .utility) {
            let active = ScreenSharingDetector.detectActiveRemoteSession()
            await MainActor.run { self.remoteSessionActive = active }
        }
    }

    private func loadAll() {
        let mgr = HotKeyManager.shared
        focusNext = mgr.savedCombo(for: .focusNext)
        focusPrev = mgr.savedCombo(for: .focusPrevious)
        moveNext = mgr.savedCombo(for: .moveNextDisplay)
        movePrev = mgr.savedCombo(for: .movePrevDisplay)
    }

    private func save(_ slot: Slot, _ combo: KeyCombo?) {
        HotKeyManager.shared.saveCombo(combo, for: slot)
        onHotkeysChanged?()
    }
}
