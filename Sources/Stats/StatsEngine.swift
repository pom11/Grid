import Foundation
import Combine
import os.log

private let log = Logger(subsystem: "ro.pom.grid", category: "stats")

@MainActor
final class StatsEngine: ObservableObject {
    static let shared = StatsEngine()

    let cpu = CPUReader()
    let gpu = GPUReader()
    let ram = RAMReader()
    let disk = DiskReader()
    let sensors = SensorReader()
    let network = NetworkReader()

    @Published var refreshInterval: TimeInterval = 2.0 {
        didSet { saveMonitorConfig(); restartTimer() }
    }

    @Published var showStats: Bool = true {
        didSet {
            saveMonitorConfig()
            if showStats { start() } else { stop() }
        }
    }

    @Published var menuBarStyle: MenuBarStyle = .dotMatrix {
        didSet { saveMonitorConfig() }
    }

    @Published var showCPU = true { didSet { saveMonitorConfig() } }
    @Published var showGPU = true { didSet { saveMonitorConfig() } }
    @Published var showRAM = true { didSet { saveMonitorConfig() } }
    @Published var showDisk = true { didSet { saveMonitorConfig() } }
    @Published var showSensors = true { didSet { saveMonitorConfig() } }
    @Published var showNetwork = true { didSet { saveMonitorConfig() } }
    @Published var fontSize: CGFloat = 10 { didSet { saveMonitorConfig() } }

    private(set) var cpuHistory: [Double] = []
    private(set) var gpuHistory: [Double] = []
    private(set) var ramHistory: [Double] = []
    private let maxHistory = 10

    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var isLoading = true

    private init() {
        let config = AppConfig.load()
        showStats = config.monitor.showStats
        menuBarStyle = config.monitor.style
        refreshInterval = config.monitor.refreshInterval
        showCPU = config.monitor.showCPU
        showGPU = config.monitor.showGPU
        showRAM = config.monitor.showRAM
        showDisk = config.monitor.showDisk
        showSensors = config.monitor.showSensors
        showNetwork = config.monitor.showNetwork
        fontSize = config.monitor.fontSize
        isLoading = false
    }

    private func saveMonitorConfig() {
        guard !isLoading else { return }
        var config = AppConfig.load()
        config.monitor = AppConfig.MonitorSettings(
            showStats: showStats,
            style: menuBarStyle,
            refreshInterval: refreshInterval,
            showCPU: showCPU,
            showGPU: showGPU,
            showRAM: showRAM,
            showDisk: showDisk,
            showSensors: showSensors,
            showNetwork: showNetwork,
            fontSize: fontSize
        )
        config.save()
    }

    func start() {
        readAll()
        restartTimer()
        log.info("Stats engine started (interval: \(self.refreshInterval)s)")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        log.info("Stats engine stopped")
    }

    private func restartTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.readAll()
            }
        }
    }

    private func readAll() {
        cpu.read()
        gpu.read()
        ram.read()
        disk.read()
        sensors.read()
        network.read()

        cpuHistory.append(cpu.usage)
        if cpuHistory.count > maxHistory { cpuHistory.removeFirst() }
        gpuHistory.append(max(gpu.usage, 0))
        if gpuHistory.count > maxHistory { gpuHistory.removeFirst() }
        let ramPct = ram.total > 0 ? Double(ram.used) / Double(ram.total) : 0
        ramHistory.append(ramPct)
        if ramHistory.count > maxHistory { ramHistory.removeFirst() }

        objectWillChange.send()
    }
}
