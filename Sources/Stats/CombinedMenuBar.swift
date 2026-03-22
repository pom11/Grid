import AppKit
import Combine
import os.log

private let log = Logger(subsystem: "ro.pom.grid", category: "menubar")

// MARK: - Menu Bar Style

enum MenuBarStyle: String, CaseIterable, Hashable, Codable {
    case sparklines
    case cleanNumbers
    case dotMatrix
    case minimal
    case twoRow

    var displayName: String {
        switch self {
        case .sparklines: "Sparklines"
        case .cleanNumbers: "Numbers"
        case .dotMatrix: "Dot Matrix"
        case .minimal: "Minimal"
        case .twoRow: "Two-Row"
        }
    }
}

// MARK: - Combined Menu Bar View

final class CombinedMenuBarView: NSView {
    private var statViews: [NSView] = []
    private var iconView: NSImageView?
    private var cancellable: AnyCancellable?
    private let engine: StatsEngine
    var onSizeChanged: ((CGFloat) -> Void)?

    private static let barHeight: CGFloat = 22
    private static let iconSize: CGFloat = 16

    // Dynamic fonts based on engine.fontSize
    private var labelFont: NSFont { .monospacedSystemFont(ofSize: engine.fontSize - 1, weight: .semibold) }
    private var smallFont: NSFont { .monospacedSystemFont(ofSize: engine.fontSize, weight: .medium) }
    private var valueFont: NSFont { .monospacedSystemFont(ofSize: engine.fontSize + 1, weight: .medium) }

    init(engine: StatsEngine) {
        self.engine = engine
        super.init(frame: .zero)

        let iv = NSImageView()
        iv.image = Self.loadMenuBarIcon()
        iv.imageScaling = .scaleProportionallyDown
        addSubview(iv)
        iconView = iv

        cancellable = engine.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.update() }

        update()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { frame.size }

    // MARK: - Data Model

    private enum StatKind {
        case pct, disk, network
    }

    private struct Item {
        let label: String
        let value: String
        let topRow: String
        let botRow: String
        let pct: Double
        let history: [Double]?
        let color: NSColor
        let kind: StatKind
        let temp: String?       // optional temp suffix (e.g. "42°")
        let tempColor: NSColor?
    }

    private func collectItems() -> [Item] {
        var items: [Item] = []
        let sensorsOn = engine.showSensors && engine.sensors.isAvailable

        if engine.showCPU {
            let p = engine.cpu.usage
            let ct = sensorsOn ? engine.sensors.cpuTemp : -1.0
            let ctStr = ct >= 0 ? StatsFormatter.temperature(ct) : nil
            items.append(Item(
                label: "CPU", value: StatsFormatter.percentage(p),
                topRow: "CPU", botRow: StatsFormatter.percentage(p),
                pct: p, history: engine.cpuHistory, color: Self.heat(p), kind: .pct,
                temp: ctStr, tempColor: ct >= 0 ? Self.tempHeat(ct) : nil
            ))
        }
        if engine.showGPU {
            let p = max(engine.gpu.usage, 0)
            let v = engine.gpu.isAvailable ? StatsFormatter.percentage(p) : "--"
            let c = engine.gpu.isAvailable ? Self.heat(p) : .secondaryLabelColor
            let gt = sensorsOn ? engine.sensors.gpuTemp : -1.0
            let gtStr = gt >= 0 ? StatsFormatter.temperature(gt) : nil
            items.append(Item(
                label: "GPU", value: v,
                topRow: "GPU", botRow: v,
                pct: p, history: engine.gpuHistory, color: c, kind: .pct,
                temp: gtStr, tempColor: gt >= 0 ? Self.tempHeat(gt) : nil
            ))
        }
        if engine.showRAM {
            let p = engine.ram.total > 0 ? Double(engine.ram.used) / Double(engine.ram.total) : 0
            items.append(Item(
                label: "RAM", value: StatsFormatter.percentage(p),
                topRow: "RAM", botRow: StatsFormatter.percentage(p),
                pct: p, history: engine.ramHistory, color: Self.heat(p), kind: .pct,
                temp: nil, tempColor: nil
            ))
        }
        if engine.showDisk {
            let p = engine.disk.total > 0 ? Double(engine.disk.used) / Double(engine.disk.total) : 0
            let v = "\(StatsFormatter.diskGB(engine.disk.used))/\(StatsFormatter.diskGB(engine.disk.total))"
            items.append(Item(
                label: "DSK", value: v,
                topRow: "DSK", botRow: v,
                pct: p, history: nil, color: Self.heat(p), kind: .disk,
                temp: nil, tempColor: nil
            ))
        }
        if engine.showNetwork {
            let up = StatsFormatter.networkSpeed(engine.network.uploadSpeed)
            let dn = StatsFormatter.networkSpeed(engine.network.downloadSpeed)
            items.append(Item(
                label: "NET", value: "↑\(up) ↓\(dn)",
                topRow: "↑\(up)", botRow: "↓\(dn)",
                pct: -1, history: nil, color: .labelColor, kind: .network,
                temp: nil, tempColor: nil
            ))
        }

        return items
    }

    // MARK: - Update

    private func update() {
        statViews.forEach { $0.removeFromSuperview() }
        statViews.removeAll()

        var x: CGFloat = 2

        if engine.showStats {
            let items = collectItems()
            if !items.isEmpty {
                switch engine.menuBarStyle {
                case .sparklines:    x = layoutA(items, x: x)
                case .cleanNumbers:  x = layoutB(items, x: x)
                case .dotMatrix:     x = layoutC(items, x: x)
                case .minimal:       x = layoutD(items, x: x)
                case .twoRow:        x = layoutE(items, x: x)
                }
            }
        }

        let iconY = (Self.barHeight - Self.iconSize) / 2
        iconView?.frame = NSRect(x: x, y: iconY, width: Self.iconSize, height: Self.iconSize)
        x += Self.iconSize + 2

        frame.size = NSSize(width: x, height: Self.barHeight)
        invalidateIntrinsicContentSize()
        onSizeChanged?(x)
    }

    // MARK: - Value template for fixed-width alignment

    private func valueTemplate(for item: Item) -> String? {
        switch item.kind {
        case .pct:     return "100%"
        case .disk:    return "999.9/999.9"
        case .network: return "↑99.9M ↓99.9M"
        }
    }

    private static let tempTemplate = "120°"

    private func rowTemplate(for item: Item, top: Bool) -> String? {
        switch item.kind {
        case .pct:     return top ? nil : "100%"
        case .disk:    return top ? nil : "999.9/999.9"
        case .network: return "↓99.9M"
        }
    }

    // MARK: - Temp suffix helper

    /// Place temp value after the main value if present
    private func placeTemp(_ item: Item, font: NSFont, x: inout CGFloat) {
        guard let t = item.temp, let tc = item.tempColor else { return }
        x += 2
        x += placeLabel(t, font: font, color: tc, at: x,
                        minTemplate: Self.tempTemplate, align: .right)
    }

    // MARK: - Style A: Sparklines + Heat Colors

    private func layoutA(_ items: [Item], x startX: CGFloat) -> CGFloat {
        var x = startX
        for (i, item) in items.enumerated() {
            x += placeLabel(item.label, font: labelFont, color: .secondaryLabelColor, at: x)
            x += 3
            if let h = item.history, !h.isEmpty {
                x += placeSparkline(h, color: item.color, height: 12, at: x)
                x += 3
            }
            x += placeLabel(item.value, font: smallFont, color: item.color, at: x,
                            minTemplate: valueTemplate(for: item), align: .right)
            placeTemp(item, font: smallFont, x: &x)
            if i < items.count - 1 { x += placeSep(at: x) } else { x += 6 }
        }
        return x
    }

    // MARK: - Style B: Clean Numbers + Heat Colors

    private func layoutB(_ items: [Item], x startX: CGFloat) -> CGFloat {
        var x = startX
        for (i, item) in items.enumerated() {
            x += placeLabel(item.label, font: labelFont, color: .secondaryLabelColor, at: x)
            x += 3
            x += placeLabel(item.value, font: valueFont, color: item.color, at: x,
                            minTemplate: valueTemplate(for: item), align: .right)
            placeTemp(item, font: valueFont, x: &x)
            if i < items.count - 1 { x += placeSep(at: x) } else { x += 6 }
        }
        return x
    }

    // MARK: - Style C: Dot Matrix

    private func layoutC(_ items: [Item], x startX: CGFloat) -> CGFloat {
        var x = startX
        for (i, item) in items.enumerated() {
            if item.pct >= 0 {
                x += placeLabel(item.label, font: labelFont, color: .secondaryLabelColor, at: x)
                x += 3
                let filled = Int(round(item.pct * 16))
                x += placeDotGrid(filled, color: item.color, at: x)
                placeTemp(item, font: labelFont, x: &x)
            } else {
                x += placeLabel(item.value, font: smallFont, color: item.color, at: x,
                                minTemplate: valueTemplate(for: item), align: .right)
            }
            if i < items.count - 1 { x += placeSep(at: x) } else { x += 6 }
        }
        return x
    }

    // MARK: - Style D: Minimal (Sparklines, No Labels)

    private func layoutD(_ items: [Item], x startX: CGFloat) -> CGFloat {
        var x = startX
        for (i, item) in items.enumerated() {
            if let h = item.history, !h.isEmpty {
                x += placeSparkline(h, color: item.color, height: 16, at: x)
                x += 2
            }
            x += placeLabel(item.value, font: smallFont, color: item.color, at: x,
                            minTemplate: valueTemplate(for: item), align: .right)
            placeTemp(item, font: smallFont, x: &x)
            if i < items.count - 1 { x += placeSep(at: x) } else { x += 6 }
        }
        return x
    }

    // MARK: - Style E: Two-Row + Sparklines

    private func layoutE(_ items: [Item], x startX: CGFloat) -> CGFloat {
        let half = Self.barHeight / 2
        var x = startX
        for (i, item) in items.enumerated() {
            if let h = item.history, !h.isEmpty {
                x += placeSparkline(h, color: item.color, height: 16, at: x)
                x += 3
            }
            let topTpl = rowTemplate(for: item, top: true)
            let botTpl = rowTemplate(for: item, top: false)

            // Top label: centered in upper half
            let topLabelFont = labelFont
            let topH = ceil(heightOf(topLabelFont))
            let topY = half + floor((half - topH) / 2)

            // Bottom label: centered in lower half
            let botLabelFont = valueFont
            let botH = ceil(heightOf(botLabelFont))
            let botY = floor((half - botH) / 2)

            // For items with temp, show "12% 42°" on bottom row
            var botText = item.botRow
            if let t = item.temp { botText += " \(t)" }
            let botTplFinal = item.temp != nil ? nil : botTpl

            let topW = placeLabel(item.topRow, font: topLabelFont, color: .secondaryLabelColor, at: x,
                                  explicitY: topY, minTemplate: topTpl, align: .right)
            let botW = placeLabel(botText, font: botLabelFont, color: item.color, at: x,
                                  explicitY: botY, minTemplate: botTplFinal, align: .right)
            x += max(topW, botW)
            if i < items.count - 1 { x += placeSep(at: x) } else { x += 6 }
        }
        return x
    }

    // MARK: - Placement Helpers

    private static var _widthCache: [String: CGFloat] = [:]

    private static func minWidth(for template: String, font: NSFont) -> CGFloat {
        let key = "\(template)|\(font.pointSize)"
        if let w = _widthCache[key] { return w }
        let tf = NSTextField(labelWithString: template)
        tf.font = font
        let w = ceil(tf.intrinsicContentSize.width) + 2
        _widthCache[key] = w
        return w
    }

    private func heightOf(_ font: NSFont) -> CGFloat {
        let tf = NSTextField(labelWithString: "X")
        tf.font = font
        return ceil(tf.intrinsicContentSize.height)
    }

    /// Place a label, vertically centered by default. Pass `explicitY` to override.
    @discardableResult
    private func placeLabel(_ text: String, font: NSFont, color: NSColor, at x: CGFloat,
                            explicitY: CGFloat? = nil,
                            minTemplate: String? = nil, align: NSTextAlignment = .left) -> CGFloat {
        let tf = NSTextField(labelWithString: text)
        tf.font = font
        tf.textColor = color
        tf.alignment = align
        tf.isBezeled = false
        tf.drawsBackground = false
        tf.isEditable = false
        tf.isSelectable = false
        var w = ceil(tf.intrinsicContentSize.width) + 2
        if let tpl = minTemplate {
            w = max(w, Self.minWidth(for: tpl, font: font))
        }
        let h = ceil(tf.intrinsicContentSize.height)
        let y = explicitY ?? floor((Self.barHeight - h) / 2)
        tf.frame = NSRect(x: x, y: y, width: w, height: h)
        addSubview(tf)
        statViews.append(tf)
        return w
    }

    private func placeSparkline(_ values: [Double], color: NSColor, height: CGFloat, at x: CGFloat) -> CGFloat {
        let w = CGFloat(values.count) * 3 - 1
        let y = floor((Self.barHeight - height) / 2)
        let view = SparklineView(values: values, color: color)
        view.frame = NSRect(x: x, y: y, width: w, height: height)
        addSubview(view)
        statViews.append(view)
        return w
    }

    private func placeDotGrid(_ filled: Int, color: NSColor, at x: CGFloat) -> CGFloat {
        let size: CGFloat = 15
        let y = floor((Self.barHeight - size) / 2)
        let view = DotGridView(filled: filled, color: color)
        view.frame = NSRect(x: x, y: y, width: size, height: size)
        addSubview(view)
        statViews.append(view)
        return size
    }

    private func placeSep(at x: CGFloat) -> CGFloat {
        let sep = NSView(frame: NSRect(x: x + 4, y: 5, width: 1, height: 12))
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
        addSubview(sep)
        statViews.append(sep)
        return 9
    }

    // MARK: - Heat Colors

    static func heat(_ pct: Double) -> NSColor {
        if pct < 0.30 { return .labelColor }
        if pct < 0.60 { return NSColor(red: 0.96, green: 0.77, blue: 0.26, alpha: 1) }
        if pct < 0.80 { return NSColor(red: 0.96, green: 0.62, blue: 0.26, alpha: 1) }
        return NSColor(red: 0.96, green: 0.26, blue: 0.26, alpha: 1)
    }

    static func tempHeat(_ celsius: Double) -> NSColor {
        if celsius < 50 { return .labelColor }
        if celsius < 70 { return NSColor(red: 0.96, green: 0.77, blue: 0.26, alpha: 1) }
        if celsius < 85 { return NSColor(red: 0.96, green: 0.62, blue: 0.26, alpha: 1) }
        return NSColor(red: 0.96, green: 0.26, blue: 0.26, alpha: 1)
    }

    // MARK: - Icon

    private static func loadMenuBarIcon() -> NSImage {
        let bundle = Bundle.module
        if let url = bundle.url(forResource: "icon_16x16@2x", withExtension: "png", subdirectory: "Assets.xcassets/AppIcon.appiconset"),
           let img = NSImage(contentsOf: url) {
            img.isTemplate = true
            img.size = NSSize(width: 16, height: 16)
            return img
        }
        let img = NSImage(systemSymbolName: "square.grid.3x3", accessibilityDescription: "Grid")!
        img.isTemplate = true
        return img
    }
}

// MARK: - Sparkline View

private class SparklineView: NSView {
    let values: [Double]
    let barColor: NSColor

    init(values: [Double], color: NSColor) {
        self.values = values
        self.barColor = color
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        barColor.withAlphaComponent(0.6).setFill()
        for (i, val) in values.enumerated() {
            let h = max(1, CGFloat(val) * bounds.height)
            let x = CGFloat(i) * 3
            let rect = NSRect(x: x, y: 0, width: 2, height: h)
            NSBezierPath(roundedRect: rect, xRadius: 0.5, yRadius: 0.5).fill()
        }
    }
}

// MARK: - Dot Grid View

private class DotGridView: NSView {
    let filled: Int
    let dotColor: NSColor

    init(filled: Int, color: NSColor) {
        self.filled = min(16, max(0, filled))
        self.dotColor = color
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        for row in 0..<4 {
            for col in 0..<4 {
                let idx = row * 4 + col
                let x = CGFloat(col) * 4
                let y = bounds.height - CGFloat(row + 1) * 4
                let rect = NSRect(x: x, y: y, width: 3, height: 3)
                if idx < filled {
                    dotColor.withAlphaComponent(0.8).setFill()
                } else {
                    NSColor.labelColor.withAlphaComponent(0.12).setFill()
                }
                NSBezierPath(ovalIn: rect).fill()
            }
        }
    }
}
