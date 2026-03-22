import SwiftUI

struct GridTab: View {
    @ObservedObject var store: ZoneStore
    @State private var gridConfig: GridConfig = .default
    @State private var editingZoneId: UUID?
    var onZonesChanged: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Margin config
                HStack {
                    Text("Margin")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Stepper(
                        "\(Int(gridConfig.margin)) pt",
                        value: $gridConfig.margin,
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
                        config: gridConfig,
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
        .onAppear { loadGridConfig() }
        .onChange(of: gridConfig.margin) { _, _ in
            saveGridConfig(gridConfig)
        }
    }

    private func addNewZone() {
        let index = store.zones.count + 1
        let zone = Zone(
            id: UUID(),
            name: "Zone \(String(format: "%02d", index))",
            gridSelection: GridRect(x: 0, y: 0, width: gridConfig.columns / 2, height: gridConfig.rows / 2),
            hotkey: nil,
            displayIndex: nil
        )
        store.zones.append(zone)
        store.save()
        onZonesChanged?()
        editingZoneId = zone.id
    }

    private func loadGridConfig() {
        gridConfig = AppConfig.load().grid
    }

    private func saveGridConfig(_ config: GridConfig) {
        var appConfig = AppConfig.load()
        appConfig.grid = config
        appConfig.save()
    }
}

// MARK: - Zone Row

struct ZoneRow: View {
    @Binding var zone: Zone
    let config: GridConfig
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
