import SwiftUI

struct MonitorTab: View {
    @ObservedObject var engine: StatsEngine

    var body: some View {
        Form {
            Section {
                Toggle("Show Stats in Menu Bar", isOn: $engine.showStats)
            }

            Section("Menu Bar Style") {
                Picker("Style", selection: $engine.menuBarStyle) {
                    ForEach(MenuBarStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.radioGroup)

                Stepper("Font Size: \(Int(engine.fontSize)) pt",
                        value: $engine.fontSize, in: 8...14, step: 1)
            }
            .disabled(!engine.showStats)

            Section("Metrics") {
                Toggle("CPU", isOn: $engine.showCPU)
                Toggle("GPU", isOn: $engine.showGPU)
                Toggle("RAM", isOn: $engine.showRAM)
                Toggle("Disk", isOn: $engine.showDisk)
                Toggle("Sensors", isOn: $engine.showSensors)
                Toggle("Network", isOn: $engine.showNetwork)
            }
            .disabled(!engine.showStats)

            Section("Refresh Interval") {
                Picker("Update every", selection: $engine.refreshInterval) {
                    Text("1 second").tag(1.0 as TimeInterval)
                    Text("2 seconds").tag(2.0 as TimeInterval)
                    Text("3 seconds").tag(3.0 as TimeInterval)
                    Text("5 seconds").tag(5.0 as TimeInterval)
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
    }
}
