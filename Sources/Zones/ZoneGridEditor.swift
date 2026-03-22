import SwiftUI

struct ZoneGridEditor: View {
    let config: GridConfig
    @Binding var selection: GridRect?
    @State private var dragStart: (Int, Int)?
    @State private var dragEnd: (Int, Int)?

    private var effectiveColumns: Int { config.columns }
    private var effectiveRows: Int { config.rows }

    var body: some View {
        GeometryReader { geo in
            let cellW = geo.size.width / CGFloat(effectiveColumns)
            let cellH = geo.size.height / CGFloat(effectiveRows)

            ZStack(alignment: .topLeading) {
                // Grid cells
                ForEach(0..<effectiveRows, id: \.self) { row in
                    ForEach(0..<effectiveColumns, id: \.self) { col in
                        let isSelected = isCellSelected(col: col, row: row)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(isSelected ? Color.accentColor.opacity(0.6) : Color.gray.opacity(0.3))
                            .frame(width: cellW - 2, height: cellH - 2)
                            .position(
                                x: CGFloat(col) * cellW + cellW / 2,
                                y: CGFloat(row) * cellH + cellH / 2
                            )
                    }
                }

                // Guide lines — half lines are stronger, quarter and third lines are subtler
                let guideColor = Color.accentColor.opacity(0.25)
                let halfColor = Color.accentColor.opacity(0.45)

                // Vertical guides (1/4, 1/2, 3/4)
                ForEach([1, 2, 3], id: \.self) { q in
                    let xPos = geo.size.width * CGFloat(q) / 4.0
                    Rectangle()
                        .fill(q == 2 ? halfColor : guideColor)
                        .frame(width: q == 2 ? 1.5 : 1, height: geo.size.height)
                        .position(x: xPos, y: geo.size.height / 2)
                        .allowsHitTesting(false)
                }

                // Horizontal guides (1/4, 1/2, 3/4)
                ForEach([1, 2, 3], id: \.self) { q in
                    let yPos = geo.size.height * CGFloat(q) / 4.0
                    Rectangle()
                        .fill(q == 2 ? halfColor : guideColor)
                        .frame(width: geo.size.width, height: q == 2 ? 1.5 : 1)
                        .position(x: geo.size.width / 2, y: yPos)
                        .allowsHitTesting(false)
                }

                // Third lines
                ForEach([1, 2], id: \.self) { t in
                    let xPos = geo.size.width * CGFloat(t) / 3.0
                    Rectangle()
                        .fill(guideColor)
                        .frame(width: 1, height: geo.size.height)
                        .position(x: xPos, y: geo.size.height / 2)
                        .allowsHitTesting(false)

                    let yPos = geo.size.height * CGFloat(t) / 3.0
                    Rectangle()
                        .fill(guideColor)
                        .frame(width: geo.size.width, height: 1)
                        .position(x: geo.size.width / 2, y: yPos)
                        .allowsHitTesting(false)
                }

                if let sel = currentSelection {
                    let fracW = simplify(sel.width, effectiveColumns)
                    let fracH = simplify(sel.height, effectiveRows)
                    VStack(spacing: 2) {
                        Text("\(fracW)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("\(fracH)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .position(
                        x: CGFloat(sel.x + sel.width) * cellW + 20,
                        y: CGFloat(sel.y + sel.height) * cellH - 10
                    )
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let col = Int(value.location.x / cellW)
                        let row = Int(value.location.y / cellH)
                        let clampedCol = max(0, min(col, effectiveColumns - 1))
                        let clampedRow = max(0, min(row, effectiveRows - 1))

                        if dragStart == nil {
                            let startCol = Int(value.startLocation.x / cellW)
                            let startRow = Int(value.startLocation.y / cellH)
                            dragStart = (
                                max(0, min(startCol, effectiveColumns - 1)),
                                max(0, min(startRow, effectiveRows - 1))
                            )
                        }
                        dragEnd = (clampedCol, clampedRow)
                    }
                    .onEnded { _ in
                        if let rect = currentSelection {
                            selection = rect
                        }
                        dragStart = nil
                        dragEnd = nil
                    }
            )
        }
        .aspectRatio(CGFloat(effectiveColumns) / CGFloat(effectiveRows), contentMode: .fit)
    }

    private var currentSelection: GridRect? {
        if let sel = selection, dragStart == nil { return sel }
        guard let start = dragStart, let end = dragEnd else { return selection }
        let minCol = min(start.0, end.0)
        let maxCol = max(start.0, end.0)
        let minRow = min(start.1, end.1)
        let maxRow = max(start.1, end.1)
        return GridRect(x: minCol, y: minRow, width: maxCol - minCol + 1, height: maxRow - minRow + 1)
    }

    private func isCellSelected(col: Int, row: Int) -> Bool {
        guard let sel = currentSelection else { return false }
        return col >= sel.x && col < sel.x + sel.width &&
               row >= sel.y && row < sel.y + sel.height
    }

    private func simplify(_ num: Int, _ den: Int) -> String {
        let g = gcd(num, den)
        return "\(num / g)/\(den / g)"
    }

    private func gcd(_ a: Int, _ b: Int) -> Int {
        b == 0 ? a : gcd(b, a % b)
    }
}
