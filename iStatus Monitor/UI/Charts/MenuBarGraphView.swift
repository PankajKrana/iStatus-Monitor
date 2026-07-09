import SwiftUI

/// A tiny, allocation-light sparkline for the menu bar label.
///
/// Hand-drawn with `Path` (deliberately *not* Swift Charts) and redrawn at most
/// once per sampling tick, so it costs virtually nothing at idle — the key to
/// keeping the menu bar under ~1% CPU. Charts-based sparklines (`SparklineView`)
/// are reserved for popovers, which open on demand.
struct MenuBarGraphView: View {
    let values: [Double]
    let color: Color
    let height: CGFloat
    let width: CGFloat

    init(values: [Double], color: Color = .primary, height: CGFloat = 15, width: CGFloat = 28) {
        self.values = values
        self.color = color
        self.height = height
        self.width = width
    }

    /// Values mapped into a padded 0.15…0.85 vertical band (so a flat line isn't
    /// glued to the bottom edge). Empty for <1 sample or a constant series.
    private var normalized: [CGFloat] {
        guard values.count > 1,
              let min = values.min(),
              let max = values.max(),
              max > min
        else {
            return values.isEmpty ? [] : Array(repeating: 0.5, count: values.count)
        }
        let range = max - min
        let pad: CGFloat = 0.15
        return values.map { CGFloat(($0 - min) / range) * (1 - 2 * pad) + pad }
    }

    var body: some View {
        let points = normalized
        Path { path in
            guard !points.isEmpty else { return }
            let step = points.count > 1 ? width / CGFloat(points.count - 1) : 0
            for (index, point) in points.enumerated() {
                let x = CGFloat(index) * step
                let y = height * (1 - point)
                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }
        .stroke(color, lineWidth: 1.25)
        .frame(width: width, height: height)
    }
}
