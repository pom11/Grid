import SwiftUI

struct HotkeysTab: View {
    @State private var focusNext: KeyCombo?
    @State private var focusPrev: KeyCombo?
    @State private var moveNext: KeyCombo?
    @State private var movePrev: KeyCombo?
    var onHotkeysChanged: (() -> Void)?

    var body: some View {
        Form {
            Section("Focus Cycling") {
                HotKeyRecorderView(label: "Focus next window", combo: $focusNext)
                    .onChange(of: focusNext) { _, val in save(.focusNext, val) }
                HotKeyRecorderView(label: "Focus previous window", combo: $focusPrev)
                    .onChange(of: focusPrev) { _, val in save(.focusPrevious, val) }
            }

            Section("Move Between Displays") {
                HotKeyRecorderView(label: "Move to next display", combo: $moveNext)
                    .onChange(of: moveNext) { _, val in save(.moveNextDisplay, val) }
                HotKeyRecorderView(label: "Move to previous display", combo: $movePrev)
                    .onChange(of: movePrev) { _, val in save(.movePrevDisplay, val) }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { loadAll() }
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
