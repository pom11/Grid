import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case monitor = "Monitor"
    case grid = "Grid"
    case hotkeys = "Hotkeys"
    case about = "About"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .monitor: return "gauge.with.dots.needle.33percent"
        case .grid: return "square.grid.3x3"
        case .hotkeys: return "keyboard"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var engine: StatsEngine
    @ObservedObject var store: ZoneStore
    var onZonesChanged: (() -> Void)?
    var onHotkeysChanged: (() -> Void)?

    @State private var selectedSection: SettingsSection? = .monitor

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selectedSection) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            Group {
                switch selectedSection ?? .monitor {
                case .monitor:
                    MonitorTab(engine: engine)
                case .grid:
                    GridTab(store: store, onZonesChanged: onZonesChanged)
                case .hotkeys:
                    HotkeysTab(onHotkeysChanged: onHotkeysChanged)
                case .about:
                    AboutTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
