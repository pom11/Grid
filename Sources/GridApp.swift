import SwiftUI
import AppKit
import os.log

private let log = Logger(subsystem: "ro.pom.grid", category: "app")

@main
struct GridApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Window("_hidden", id: "hidden") { EmptyView().frame(width: 0, height: 0) }
            .defaultSize(width: 0, height: 0)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var statsEngine: StatsEngine!
    private let hotKeyManager = HotKeyManager.shared
    private let zoneStore = ZoneStore.shared
    private var settingsWindow: NSWindow?
    private var menuBarView: CombinedMenuBarView?
    private var cachedGridConfig: GridConfig?

    func applicationDidFinishLaunching(_ notification: Notification) {
        log.info("Grid launching")
        stripMenuBar()
        DispatchQueue.main.async {
            for window in NSApp.windows where window.title == "_hidden" || window.title.isEmpty {
                window.close()
            }
        }
        Task { @MainActor in
            statsEngine = StatsEngine.shared
            setupStatusItem()
            log.info("Status item ready")
            if statsEngine.showStats {
                statsEngine.start()
            }
            checkAccessibility()
            setupHotKeys()
            UpdateChecker.checkOnLaunchIfNeeded()
            log.info("Grid launch complete — \(self.zoneStore.zones.count) zones loaded")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        log.info("Grid terminating")
        statsEngine?.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettingsWindow()
        return true
    }

    // MARK: - Menu Bar

    private func stripMenuBar() {
        guard let mainMenu = NSApp.mainMenu else { return }

        while mainMenu.items.count > 1 {
            mainMenu.removeItem(at: mainMenu.items.count - 1)
        }

        if let appMenu = mainMenu.items.first?.submenu {
            appMenu.items.removeAll()
            appMenu.addItem(
                withTitle: "Quit Grid",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        }
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let view = CombinedMenuBarView(engine: statsEngine)
        menuBarView = view
        statusItem.button?.addSubview(view)
        statusItem.button?.frame = view.frame
        statusItem.length = view.intrinsicContentSize.width
        view.onSizeChanged = { [weak self] width in
            self?.statusItem.length = width
        }

        if let button = statusItem.button {
            button.action = #selector(statusItemClicked)
            button.target = self

            view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                view.topAnchor.constraint(equalTo: button.topAnchor),
                view.bottomAnchor.constraint(equalTo: button.bottomAnchor),
            ])
        }
    }

    // MARK: - Accessibility

    private func checkAccessibility() {
        if AccessibilityEngine.isTrusted {
            log.info("Accessibility: trusted")
        } else {
            log.warning("Accessibility: not trusted — requesting permission")
            AccessibilityEngine.requestPermission()
        }
    }

    // MARK: - Hotkeys

    private func setupHotKeys() {
        log.debug("Setting up hotkeys")
        let baseSlots: [Slot] = [.focusNext, .focusPrevious, .moveNextDisplay, .movePrevDisplay]
        for slot in baseSlots {
            if let combo = hotKeyManager.savedCombo(for: slot) {
                let handler: () -> Void
                switch slot {
                case .focusNext:
                    handler = { WindowCycler.cycleFocus(direction: 1) }
                case .focusPrevious:
                    handler = { WindowCycler.cycleFocus(direction: -1) }
                case .moveNextDisplay:
                    handler = { WindowSnapper.moveToDisplay(direction: 1) }
                case .movePrevDisplay:
                    handler = { WindowSnapper.moveToDisplay(direction: -1) }
                case .zone:
                    continue
                }
                hotKeyManager.register(slot: slot, combo: combo, handler: handler)
            }
        }
        registerZoneHotKeys()
    }

    func registerZoneHotKeys() {
        log.debug("Registering zone hotkeys for \(self.zoneStore.zones.count) zones")
        // Unregister all existing zone hotkeys first (IDs 100+)
        for i in 0..<50 {
            hotKeyManager.unregister(id: Slot.zoneSlotId(for: i))
        }
        for (i, zone) in zoneStore.zones.enumerated() {
            guard let combo = zone.hotkey else { continue }
            let capturedZone = zone
            hotKeyManager.register(id: Slot.zoneSlotId(for: i), combo: combo) { [weak self] in
                guard let self else { return }
                WindowSnapper.snap(to: capturedZone, config: self.gridConfig)
            }
        }
    }

    var gridConfig: GridConfig {
        if let cached = cachedGridConfig { return cached }
        let config = AppConfig.load().grid
        cachedGridConfig = config
        return config
    }

    func invalidateGridConfig() {
        cachedGridConfig = nil
    }

    // MARK: - Settings Window

    @MainActor
    @objc private func statusItemClicked() {
        showSettingsWindow()
    }

    @MainActor
    func showSettingsWindow() {
        log.debug("Opening settings window")
        if settingsWindow == nil {
            let view = SettingsView(
                engine: statsEngine,
                store: zoneStore,
                onZonesChanged: { [weak self] in
                    self?.invalidateGridConfig()
                    self?.registerZoneHotKeys()
                },
                onHotkeysChanged: { [weak self] in self?.setupHotKeys() }
            )

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Grid"
            window.contentView = NSHostingView(rootView: view)
            window.center()
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 600, height: 450)
            // Clear any stale autosaved frame, then re-enable
            NSWindow.removeFrame(usingName: "GridSettingsWindow")
            window.setFrameAutosaveName("GridSettingsWindow")

            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { _ in
                NSApp.setActivationPolicy(.accessory)
            }

            settingsWindow = window
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
