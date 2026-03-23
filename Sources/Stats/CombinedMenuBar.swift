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
// Single-view architecture: draws everything in one draw(_:) call
// to avoid expensive NSStatusItem replicant snapshot traversal.

final class CombinedMenuBarView: NSView {
    private var cancellable: AnyCancellable?
    private let engine: StatsEngine
    private var iconView: NSImageView?
    var onSizeChanged: ((CGFloat) -> Void)?

    private static let barHeight: CGFloat = 22
    private static let iconSize: CGFloat = 16

    // Cached fonts and metrics
    private var cachedFontSize: CGFloat = 0
    private var _labelFont: NSFont = .monospacedSystemFont(ofSize: 9, weight: .semibold)
    private var _smallFont: NSFont = .monospacedSystemFont(ofSize: 10, weight: .medium)
    private var _valueFont: NSFont = .monospacedSystemFont(ofSize: 11, weight: .medium)
    private var _labelAttrs: [NSAttributedString.Key: Any] = [:]
    private var _smallAttrs: [NSAttributedString.Key: Any] = [:]
    private var _valueAttrs: [NSAttributedString.Key: Any] = [:]

    private func updateFonts() {
        let size = engine.fontSize
        guard size != cachedFontSize else { return }
        cachedFontSize = size
        _labelFont = .monospacedSystemFont(ofSize: size - 1, weight: .semibold)
        _smallFont = .monospacedSystemFont(ofSize: size, weight: .medium)
        _valueFont = .monospacedSystemFont(ofSize: size + 1, weight: .medium)
        _labelAttrs = [.font: _labelFont]
        _smallAttrs = [.font: _smallFont]
        _valueAttrs = [.font: _valueFont]
    }

    // Width cache for fixed-width alignment templates
    private static var _widthCache: [String: CGFloat] = [:]
    private static var _heightCache: [CGFloat: CGFloat] = [:]

    private static func minWidth(for template: String, font: NSFont) -> CGFloat {
        let key = "\(template)|\(font.pointSize)"
        if let w = _widthCache[key] { return w }
        let w = ceil((template as NSString).size(withAttributes: [.font: font]).width) + 2
        _widthCache[key] = w
        return w
    }

    private static func heightOf(_ font: NSFont) -> CGFloat {
        let size = font.pointSize
        if let h = _heightCache[size] { return h }
        let h = ceil(("X" as NSString).size(withAttributes: [.font: font]).height)
        _heightCache[size] = h
        return h
    }

    init(engine: StatsEngine) {
        self.engine = engine
        super.init(frame: .zero)

        let iv = NSImageView()
        iv.image = Self.loadMenuBarIcon()
        iv.imageScaling = .scaleProportionallyDown
        addSubview(iv)
        iconView = iv

        updateFonts()

        cancellable = engine.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateSize()
                self?.needsDisplay = true
            }

        updateSize()
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
        let temp: String?
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

    // MARK: - Size Calculation

    private func updateSize() {
        updateFonts()
        let items = engine.showStats ? collectItems() : []
        var x = computeWidth(items)

        // Position icon
        let iconY = (Self.barHeight - Self.iconSize) / 2
        iconView?.frame = NSRect(x: x, y: iconY, width: Self.iconSize, height: Self.iconSize)
        x += Self.iconSize + 2

        let newSize = NSSize(width: x, height: Self.barHeight)
        if frame.size != newSize {
            frame.size = newSize
            invalidateIntrinsicContentSize()
            onSizeChanged?(x)
        }
    }

    private func computeWidth(_ items: [Item]) -> CGFloat {
        var x: CGFloat = 2
        guard !items.isEmpty else { return x }

        switch engine.menuBarStyle {
        case .sparklines:    x = widthA(items, x: x)
        case .cleanNumbers:  x = widthB(items, x: x)
        case .dotMatrix:     x = widthC(items, x: x)
        case .minimal:       x = widthD(items, x: x)
        case .twoRow:        x = widthE(items, x: x)
        }
        return x
    }

    // MARK: - Draw

    override func draw(_ dirtyRect: NSRect) {
        updateFonts()
        let items = engine.showStats ? collectItems() : []
        var x: CGFloat = 2

        if !items.isEmpty {
            switch engine.menuBarStyle {
            case .sparklines:    x = drawA(items, x: x)
            case .cleanNumbers:  x = drawB(items, x: x)
            case .dotMatrix:     x = drawC(items, x: x)
            case .minimal:       x = drawD(items, x: x)
            case .twoRow:        x = drawE(items, x: x)
            }
        }

        // Icon is drawn by its NSImageView (handles template tinting)
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

    // MARK: - Drawing Primitives

    @discardableResult
    private func drawText(_ text: String, font: NSFont, color: NSColor, at x: CGFloat,
                          explicitY: CGFloat? = nil,
                          minTemplate: String? = nil, align: NSTextAlignment = .left) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let textSize = (text as NSString).size(withAttributes: attrs)
        var w = ceil(textSize.width) + 2
        if let tpl = minTemplate {
            w = max(w, Self.minWidth(for: tpl, font: font))
        }
        let h = ceil(textSize.height)
        let y = explicitY ?? floor((Self.barHeight - h) / 2)

        var drawX = x
        if align == .right {
            drawX = x + w - ceil(textSize.width) - 1
        }
        (text as NSString).draw(at: NSPoint(x: drawX, y: y), withAttributes: attrs)
        return w
    }

    private func drawSparkline(_ values: [Double], color: NSColor, height: CGFloat, at x: CGFloat) -> CGFloat {
        let w = CGFloat(values.count) * 3 - 1
        let baseY = floor((Self.barHeight - height) / 2)
        color.withAlphaComponent(0.6).setFill()
        for (i, val) in values.enumerated() {
            let h = max(1, CGFloat(val) * height)
            let barX = x + CGFloat(i) * 3
            let rect = NSRect(x: barX, y: baseY, width: 2, height: h)
            NSBezierPath(roundedRect: rect, xRadius: 0.5, yRadius: 0.5).fill()
        }
        return w
    }

    private func drawDotGrid(_ filled: Int, color: NSColor, at x: CGFloat) -> CGFloat {
        let size: CGFloat = 15
        let baseY = floor((Self.barHeight - size) / 2)
        let clamped = min(16, max(0, filled))
        for row in 0..<4 {
            for col in 0..<4 {
                let idx = row * 4 + col
                let dotX = x + CGFloat(col) * 4
                let dotY = baseY + size - CGFloat(row + 1) * 4
                let rect = NSRect(x: dotX, y: dotY, width: 3, height: 3)
                if idx < clamped {
                    color.withAlphaComponent(0.8).setFill()
                } else {
                    NSColor.labelColor.withAlphaComponent(0.12).setFill()
                }
                NSBezierPath(ovalIn: rect).fill()
            }
        }
        return size
    }

    private func drawSep(at x: CGFloat) -> CGFloat {
        NSColor.labelColor.withAlphaComponent(0.08).setFill()
        NSRect(x: x + 4, y: 5, width: 1, height: 12).fill()
        return 9
    }

    /// Draw temp value after the main value if present
    private func drawTemp(_ item: Item, font: NSFont, x: inout CGFloat) {
        guard let t = item.temp, let tc = item.tempColor else { return }
        x += 2
        x += drawText(t, font: font, color: tc, at: x,
                       minTemplate: Self.tempTemplate, align: .right)
    }

    // MARK: - Style A: Sparklines + Heat Colors

    private func drawA(_ items: [Item], x startX: CGFloat) -> CGFloat {
        var x = startX
        for (i, item) in items.enumerated() {
            x += drawText(item.label, font: _labelFont, color: .secondaryLabelColor, at: x)
            x += 3
            if let h = item.history, !h.isEmpty {
                x += drawSparkline(h, color: item.color, height: 12, at: x)
                x += 3
            }
            x += drawText(item.value, font: _smallFont, color: item.color, at: x,
                           minTemplate: valueTemplate(for: item), align: .right)
            drawTemp(item, font: _smallFont, x: &x)
            if i < items.count - 1 { x += drawSep(at: x) } else { x += 6 }
        }
        return x
    }

    // MARK: - Style B: Clean Numbers + Heat Colors

    private func drawB(_ items: [Item], x startX: CGFloat) -> CGFloat {
        var x = startX
        for (i, item) in items.enumerated() {
            x += drawText(item.label, font: _labelFont, color: .secondaryLabelColor, at: x)
            x += 3
            x += drawText(item.value, font: _valueFont, color: item.color, at: x,
                           minTemplate: valueTemplate(for: item), align: .right)
            drawTemp(item, font: _valueFont, x: &x)
            if i < items.count - 1 { x += drawSep(at: x) } else { x += 6 }
        }
        return x
    }

    // MARK: - Style C: Dot Matrix

    private func drawC(_ items: [Item], x startX: CGFloat) -> CGFloat {
        var x = startX
        for (i, item) in items.enumerated() {
            if item.pct >= 0 {
                x += drawText(item.label, font: _labelFont, color: .secondaryLabelColor, at: x)
                x += 3
                let filled = Int(round(item.pct * 16))
                x += drawDotGrid(filled, color: item.color, at: x)
                drawTemp(item, font: _labelFont, x: &x)
            } else {
                x += drawText(item.value, font: _smallFont, color: item.color, at: x,
                               minTemplate: valueTemplate(for: item), align: .right)
            }
            if i < items.count - 1 { x += drawSep(at: x) } else { x += 6 }
        }
        return x
    }

    // MARK: - Style D: Minimal (Sparklines, No Labels)

    private func drawD(_ items: [Item], x startX: CGFloat) -> CGFloat {
        var x = startX
        for (i, item) in items.enumerated() {
            if let h = item.history, !h.isEmpty {
                x += drawSparkline(h, color: item.color, height: 16, at: x)
                x += 2
            }
            x += drawText(item.value, font: _smallFont, color: item.color, at: x,
                           minTemplate: valueTemplate(for: item), align: .right)
            drawTemp(item, font: _smallFont, x: &x)
            if i < items.count - 1 { x += drawSep(at: x) } else { x += 6 }
        }
        return x
    }

    // MARK: - Style E: Two-Row + Sparklines

    private func drawE(_ items: [Item], x startX: CGFloat) -> CGFloat {
        let half = Self.barHeight / 2
        var x = startX
        for (i, item) in items.enumerated() {
            if let h = item.history, !h.isEmpty {
                x += drawSparkline(h, color: item.color, height: 16, at: x)
                x += 3
            }
            let topTpl = rowTemplate(for: item, top: true)
            let botTpl = rowTemplate(for: item, top: false)

            let topH = ceil(Self.heightOf(_labelFont))
            let topY = half + floor((half - topH) / 2)

            let botH = ceil(Self.heightOf(_valueFont))
            let botY = floor((half - botH) / 2)

            var botText = item.botRow
            if let t = item.temp { botText += " \(t)" }
            let botTplFinal = item.temp != nil ? nil : botTpl

            let topW = drawText(item.topRow, font: _labelFont, color: .secondaryLabelColor, at: x,
                                explicitY: topY, minTemplate: topTpl, align: .right)
            let botW = drawText(botText, font: _valueFont, color: item.color, at: x,
                                explicitY: botY, minTemplate: botTplFinal, align: .right)
            x += max(topW, botW)
            if i < items.count - 1 { x += drawSep(at: x) } else { x += 6 }
        }
        return x
    }

    // MARK: - Width Calculation (mirrors draw but without drawing)

    private func textWidth(_ text: String, font: NSFont, minTemplate: String? = nil) -> CGFloat {
        var w = ceil((text as NSString).size(withAttributes: [.font: font]).width) + 2
        if let tpl = minTemplate {
            w = max(w, Self.minWidth(for: tpl, font: font))
        }
        return w
    }

    private func tempWidth(_ item: Item, font: NSFont) -> CGFloat {
        guard item.temp != nil else { return 0 }
        return 2 + textWidth(Self.tempTemplate, font: font)
    }

    private func widthA(_ items: [Item], x startX: CGFloat) -> CGFloat {
        var x = startX
        for (i, item) in items.enumerated() {
            x += textWidth(item.label, font: _labelFont) + 3
            if let h = item.history, !h.isEmpty { x += CGFloat(h.count) * 3 - 1 + 3 }
            x += textWidth(item.value, font: _smallFont, minTemplate: valueTemplate(for: item))
            x += tempWidth(item, font: _smallFont)
            x += (i < items.count - 1) ? 9 : 6
        }
        return x
    }

    private func widthB(_ items: [Item], x startX: CGFloat) -> CGFloat {
        var x = startX
        for (i, item) in items.enumerated() {
            x += textWidth(item.label, font: _labelFont) + 3
            x += textWidth(item.value, font: _valueFont, minTemplate: valueTemplate(for: item))
            x += tempWidth(item, font: _valueFont)
            x += (i < items.count - 1) ? 9 : 6
        }
        return x
    }

    private func widthC(_ items: [Item], x startX: CGFloat) -> CGFloat {
        var x = startX
        for (i, item) in items.enumerated() {
            if item.pct >= 0 {
                x += textWidth(item.label, font: _labelFont) + 3 + 15
                x += tempWidth(item, font: _labelFont)
            } else {
                x += textWidth(item.value, font: _smallFont, minTemplate: valueTemplate(for: item))
            }
            x += (i < items.count - 1) ? 9 : 6
        }
        return x
    }

    private func widthD(_ items: [Item], x startX: CGFloat) -> CGFloat {
        var x = startX
        for (i, item) in items.enumerated() {
            if let h = item.history, !h.isEmpty { x += CGFloat(h.count) * 3 - 1 + 2 }
            x += textWidth(item.value, font: _smallFont, minTemplate: valueTemplate(for: item))
            x += tempWidth(item, font: _smallFont)
            x += (i < items.count - 1) ? 9 : 6
        }
        return x
    }

    private func widthE(_ items: [Item], x startX: CGFloat) -> CGFloat {
        var x = startX
        for (i, item) in items.enumerated() {
            if let h = item.history, !h.isEmpty { x += CGFloat(h.count) * 3 - 1 + 3 }
            let topTpl = rowTemplate(for: item, top: true)
            let botTpl = rowTemplate(for: item, top: false)
            var botText = item.botRow
            if let t = item.temp { botText += " \(t)" }
            let botTplFinal = item.temp != nil ? nil : botTpl
            let topW = textWidth(item.topRow, font: _labelFont, minTemplate: topTpl)
            let botW = textWidth(botText, font: _valueFont, minTemplate: botTplFinal)
            x += max(topW, botW)
            x += (i < items.count - 1) ? 9 : 6
        }
        return x
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
        if let url = Bundle.main.url(forResource: "menubar_icon", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            img.isTemplate = true
            img.size = NSSize(width: 16, height: 16)
            return img
        }
        let img = NSImage(systemSymbolName: "number", accessibilityDescription: "Grid")!
        img.isTemplate = true
        return img
    }
}
