import Foundation

struct AppConfig: Codable, Equatable {
    var grid: GridConfig = .default
    var displayGrids: [DisplayGridConfig] = []
    var monitor = MonitorSettings()
    var hotkeys = HotkeySettings()

    struct DisplayGridConfig: Codable, Equatable {
        var displayIndex: Int
        var preset: GridPreset = .standard
        var vertical: Bool = false

        var gridConfig: GridConfig {
            var config = GridConfig(preset: preset, vertical: vertical)
            config.applyPreset()
            return config
        }
    }

    func gridConfig(for displayIndex: Int) -> GridConfig {
        var config: GridConfig
        if let dg = displayGrids.first(where: { $0.displayIndex == displayIndex }) {
            config = dg.gridConfig
        } else {
            config = grid
        }
        config.margin = grid.margin  // margin is global
        return config
    }

    struct MonitorSettings: Codable, Equatable {
        var showStats: Bool = true
        var style: MenuBarStyle = .dotMatrix
        var refreshInterval: TimeInterval = 2.0
        var showCPU: Bool = true
        var showGPU: Bool = true
        var showRAM: Bool = true
        var showDisk: Bool = true
        var showSensors: Bool = true
        var showNetwork: Bool = true
        var fontSize: CGFloat = 10

        init(showStats: Bool = true, style: MenuBarStyle = .dotMatrix,
             refreshInterval: TimeInterval = 2.0,
             showCPU: Bool = true, showGPU: Bool = true, showRAM: Bool = true,
             showDisk: Bool = true, showSensors: Bool = true, showNetwork: Bool = true,
             fontSize: CGFloat = 10) {
            self.showStats = showStats
            self.style = style
            self.refreshInterval = refreshInterval
            self.showCPU = showCPU
            self.showGPU = showGPU
            self.showRAM = showRAM
            self.showDisk = showDisk
            self.showSensors = showSensors
            self.showNetwork = showNetwork
            self.fontSize = fontSize
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            showStats = try c.decodeIfPresent(Bool.self, forKey: .showStats) ?? true
            style = try c.decodeIfPresent(MenuBarStyle.self, forKey: .style) ?? .dotMatrix
            refreshInterval = try c.decodeIfPresent(TimeInterval.self, forKey: .refreshInterval) ?? 2.0
            showCPU = try c.decodeIfPresent(Bool.self, forKey: .showCPU) ?? true
            showGPU = try c.decodeIfPresent(Bool.self, forKey: .showGPU) ?? true
            showRAM = try c.decodeIfPresent(Bool.self, forKey: .showRAM) ?? true
            showDisk = try c.decodeIfPresent(Bool.self, forKey: .showDisk) ?? true
            showSensors = try c.decodeIfPresent(Bool.self, forKey: .showSensors) ?? true
            showNetwork = try c.decodeIfPresent(Bool.self, forKey: .showNetwork) ?? true
            fontSize = try c.decodeIfPresent(CGFloat.self, forKey: .fontSize) ?? 10
        }
    }

    struct HotkeySettings: Codable, Equatable {
        // ⌃⌥→ / ⌃⌥←
        var focusNext: KeyCombo? = KeyCombo(keyCode: 0x7C, modifiers: 0x1800)
        var focusPrevious: KeyCombo? = KeyCombo(keyCode: 0x7B, modifiers: 0x1800)
        // ⌃⌥⌘→ / ⌃⌥⌘←
        var moveNextDisplay: KeyCombo? = KeyCombo(keyCode: 0x7C, modifiers: 0x1900)
        var movePrevDisplay: KeyCombo? = KeyCombo(keyCode: 0x7B, modifiers: 0x1900)
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        grid = try c.decodeIfPresent(GridConfig.self, forKey: .grid) ?? .default
        displayGrids = try c.decodeIfPresent([DisplayGridConfig].self, forKey: .displayGrids) ?? []
        monitor = try c.decodeIfPresent(MonitorSettings.self, forKey: .monitor) ?? MonitorSettings()
        hotkeys = try c.decodeIfPresent(HotkeySettings.self, forKey: .hotkeys) ?? HotkeySettings()
    }

    // MARK: - Persistence

    static let fileURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/grid/config.json")
    }()

    static func load() -> AppConfig {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            let config = AppConfig()
            config.save()
            return config
        }
        return config
    }

    func save() {
        let dir = Self.fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }
}
