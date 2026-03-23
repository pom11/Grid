# Presets Feature

A preset is a saved layout that arranges multiple windows into specific grid positions in one action, triggered by a global hotkey.

## Data Model

- [ ] `Preset` struct: id (UUID), name (String), hotkey (KeyCombo?), entries ([PresetEntry])
- [ ] `PresetEntry` struct: appBundleID (String), appName (String), gridSelection (GridRect), matchRule (MatchRule), displayIndex (Int?)
- [ ] `MatchRule` enum: .any (first window found), .title(String), .index(Int)
- [ ] Storage: `~/.config/grid/presets.json`

## Core Logic

- [ ] `PresetStore` (like ZoneStore): load/save presets, @Published for SwiftUI binding
- [ ] `PresetApplier`: iterates entries, finds matching windows via AccessibilityEngine, snaps each to its gridSelection
- [ ] Window matching: by bundleID + MatchRule (.any = first window, .title = title contains, .index = positional)
- [ ] Skip entries where the target app isn't running (no launch, for now)

## Hotkey Integration

- [ ] Register preset hotkeys in HotKeyManager alongside zone hotkeys
- [ ] Each preset gets one global hotkey that applies the full layout

## Settings UI

- [ ] "Presets" tab in SettingsWindow
- [ ] List of presets (add/remove/rename)
- [ ] Per preset: list of entries (app picker + grid rect drawn in ZoneGridEditor + match rule)
- [ ] Hotkey recorder per preset
- [ ] Reuse ZoneGridEditor for drawing each entry's grid rect

## Future (out of scope for now)

- [ ] Launch apps that aren't running before snapping
- [ ] Import/export presets
- [ ] Preset chaining or scheduling
