import SwiftUI
import ServiceManagement

struct AboutTab: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var updateStatus: String?
    @State private var autoCheckEnabled = UserDefaults.standard.object(forKey: "autoCheckForUpdates") as? Bool ?? true

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Grid").font(.headline)
                        Text("v\(appVersion)").foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                LabeledContent("Bundle ID", value: Bundle.main.bundleIdentifier ?? "?")
            }

            Section {
                LabeledContent("GitHub") {
                    Link("pom11/Grid", destination: URL(string: "https://github.com/pom11/Grid")!)
                }
                LabeledContent("Homebrew") {
                    Text("pom11/tap/grid")
                        .textSelection(.enabled)
                }
                LabeledContent("License", value: "MIT")
            }

            Section {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = !newValue
                        }
                    }
            }

            Section {
                Toggle("Check for updates on launch", isOn: $autoCheckEnabled)
                    .onChange(of: autoCheckEnabled) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: "autoCheckForUpdates")
                    }
                HStack(spacing: 8) {
                    Button {
                        UpdateChecker.check { status in
                            updateStatus = status
                        }
                    } label: {
                        Text("Check Now")
                    }
                    if let status = updateStatus {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Updates")
            } footer: {
                Text("Run `brew upgrade --cask grid` to update.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("About")
        .onAppear {
            if let cached = UpdateChecker.lastStatus {
                updateStatus = cached
            }
        }
    }
}

// MARK: - Update Checker

enum UpdateChecker {
    static var lastStatus: String?

    static func check(completion: ((String) -> Void)? = nil) {
        completion?("Checking...")
        Task {
            do {
                let url = URL(string: "https://api.github.com/repos/pom11/Grid/releases/latest")!
                let (data, _) = try await URLSession.shared.data(from: url)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let tag = json["tag_name"] as? String {
                    let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
                    let status: String
                    if latest == appVersion {
                        status = "Up to date"
                    } else {
                        status = "v\(latest) available"
                    }
                    lastStatus = status
                    UserDefaults.standard.set(Date(), forKey: "lastUpdateCheck")
                    await MainActor.run { completion?(status) }
                }
            } catch {
                await MainActor.run { completion?("Check failed") }
            }
        }
    }

    static func checkOnLaunchIfNeeded() {
        guard UserDefaults.standard.object(forKey: "autoCheckForUpdates") as? Bool ?? true else { return }
        check()
    }
}
