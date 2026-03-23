import SwiftUI

struct GridTab: View {
    @ObservedObject var store: ZoneStore
    @State private var appConfig: AppConfig = .init()
    @State private var editingZoneId: UUID?
    var onZonesChanged: (() -> Void)?

    private var screens: [NSScreen] { ScreenHelper.sortedScreens }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Per-display grid configs
                ForEach(Array(screens.enumerated()), id: \.offset) { index, screen in
                    DisplayGridRow(
                        displayIndex: index,
                        screenName: screenName(screen, index: index),
                        config: displayGridBinding(for: index)
                    )
                    Divider()
                }

                // Global margin
                HStack {
                    Text("Margin")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Stepper(
                        "\(Int(appConfig.grid.margin)) pt",
                        value: $appConfig.grid.margin,
                        in: 0...20,
                        step: 2
                    )
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Divider()

                // Zone rows
                ForEach($store.zones) { $zone in
                    ZoneRow(
                        zone: $zone,
                        config: gridConfig(for: zone),
                        displayCount: screens.count,
                        isEditing: editingZoneId == zone.id,
                        onEdit: { editingZoneId = zone.id },
                        onSave: {
                            editingZoneId = nil
                            store.save()
                            onZonesChanged?()
                        },
                        onDelete: {
                            if editingZoneId == zone.id { editingZoneId = nil }
                            store.zones.removeAll { $0.id == zone.id }
                            store.save()
                            onZonesChanged?()
                        }
                    )
                    Divider()
                }

                // Add zone
                Button(action: addNewZone) {
                    Label("Add Zone", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
        .onAppear { appConfig = AppConfig.load() }
        .onChange(of: appConfig.grid.margin) { _, _ in saveConfig() }
        .onChange(of: appConfig.displayGrids) { _, _ in saveConfig() }
    }

    private func gridConfig(for zone: Zone) -> GridConfig {
        if let di = zone.displayIndex {
            return appConfig.gridConfig(for: di)
        }
        return appConfig.grid
    }

    private func displayGridBinding(for index: Int) -> Binding<AppConfig.DisplayGridConfig> {
        Binding(
            get: {
                appConfig.displayGrids.first { $0.displayIndex == index }
                    ?? AppConfig.DisplayGridConfig(displayIndex: index)
            },
            set: { newValue in
                if let i = appConfig.displayGrids.firstIndex(where: { $0.displayIndex == index }) {
                    appConfig.displayGrids[i] = newValue
                } else {
                    appConfig.displayGrids.append(newValue)
                }
            }
        )
    }

    private func screenName(_ screen: NSScreen, index: Int) -> String {
        let name = screen.localizedName
        return "Display \(index + 1) — \(name)"
    }

    private func addNewZone() {
        let defaultConfig = appConfig.gridConfig(for: 0)
        let index = store.zones.count + 1
        let zone = Zone(
            id: UUID(),
            name: "Zone \(String(format: "%02d", index))",
            gridSelection: GridRect(x: 0, y: 0, width: defaultConfig.columns / 2, height: defaultConfig.rows / 2),
            hotkey: nil,
            displayIndex: nil
        )
        store.zones.append(zone)
        store.save()
        onZonesChanged?()
        editingZoneId = zone.id
    }

    private func saveConfig() {
        appConfig.save()
        onZonesChanged?()
    }
}

// MARK: - Display Grid Row

struct DisplayGridRow: View {
    let displayIndex: Int
    let screenName: String
    @Binding var config: AppConfig.DisplayGridConfig

    var body: some View {
        HStack {
            Text(screenName)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Picker("", selection: $config.preset) {
                ForEach(GridPreset.allCases, id: \.self) { preset in
                    Text(preset.label).tag(preset)
                }
            }
            .labelsHidden()
            .frame(width: 190)

            Toggle("Vertical", isOn: $config.vertical)
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Zone Row

struct ZoneRow: View {
    @Binding var zone: Zone
    let config: GridConfig
    var displayCount: Int = 1
    let isEditing: Bool
    let onEdit: () -> Void
    let onSave: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Collapsed row — always visible
            HStack {
                ZoneThumbnail(zone: zone, config: config)

                Text(zone.name)
                    .fontWeight(.medium)

                if let di = zone.displayIndex {
                    Text("D\(di + 1)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color(nsColor: .quaternaryLabelColor))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }

                Spacer()

                if let combo = zone.hotkey {
                    Text(combo.displayString)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color(nsColor: .quaternaryLabelColor))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }

                Button(isEditing ? "Done" : "Edit") {
                    if isEditing { onSave() } else { onEdit() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // Expanded editor
            if isEditing {
                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    // Name
                    HStack {
                        Text("Name")
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .leading)
                        TextField("Zone name", text: $zone.name)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Display picker
                    if displayCount > 1 {
                        HStack {
                            Text("Display")
                                .foregroundStyle(.secondary)
                                .frame(width: 80, alignment: .leading)
                            Picker("", selection: Binding(
                                get: { zone.displayIndex ?? -1 },
                                set: { zone.displayIndex = $0 == -1 ? nil : $0 }
                            )) {
                                Text("Current").tag(-1)
                                ForEach(0..<displayCount, id: \.self) { i in
                                    Text("Display \(i + 1)").tag(i)
                                }
                            }
                            .labelsHidden()
                        }
                    }

                    // Grid editor
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Position & Size")
                            .foregroundStyle(.secondary)
                        ZoneGridEditor(config: config, selection: Binding(
                            get: { zone.gridSelection as GridRect? },
                            set: { if let r = $0 { zone.gridSelection = r } }
                        ))
                        .frame(height: 280)
                    }

                    // Shortcut
                    HStack {
                        Text("Shortcut")
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .leading)
                        HotKeyRecorderView(label: "", combo: $zone.hotkey)
                    }

                    // Actions
                    HStack {
                        Button(role: .destructive, action: onDelete) {
                            Label("Delete Zone", systemImage: "trash")
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(.red)

                        Spacer()

                        Button("Save", action: onSave)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .background(isEditing ? Color(nsColor: .controlBackgroundColor) : .clear)
    }
}

// MARK: - Zone Thumbnail

struct ZoneThumbnail: View {
    let zone: Zone
    let config: GridConfig

    private let thumbWidth: CGFloat = 28
    private let thumbHeight: CGFloat = 16

    var body: some View {
        Canvas { context, size in
            let cellW = size.width / CGFloat(config.columns)
            let cellH = size.height / CGFloat(config.rows)

            // Background
            context.fill(
                Path(roundedRect: CGRect(origin: .zero, size: size),
                     cornerSize: CGSize(width: 2, height: 2)),
                with: .color(Color(nsColor: .quaternaryLabelColor))
            )

            // Zone highlight
            let sel = zone.gridSelection
            let rect = CGRect(
                x: CGFloat(sel.x) * cellW,
                y: CGFloat(sel.y) * cellH,
                width: CGFloat(sel.width) * cellW,
                height: CGFloat(sel.height) * cellH
            )
            context.fill(
                Path(roundedRect: rect, cornerSize: CGSize(width: 1, height: 1)),
                with: .color(.accentColor.opacity(0.8))
            )
        }
        .frame(width: thumbWidth, height: thumbHeight)
    }
}
