import SwiftUI

/// A reusable grouped surface for metric panels.
struct GlassCard<Content: View>: View {
    let content: Content
    var material: Material = .thin
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 10

    init(
        material: Material = .thin,
        padding: CGFloat = 16,
        cornerRadius: CGFloat = 10,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.material = material
        self.padding = padding
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .padding(padding)
            // Render the caller's chosen material as the actual card surface (the
            // `material:` argument was previously stored but ignored). A hairline
            // border gives the grouped surface definition in both appearances,
            // matching native macOS card/sidebar treatment.
            .background(material, in: shape)
            .overlay(shape.strokeBorder(.separator, lineWidth: 0.5))
    }
}

#Preview {
    GlassCard {
        VStack(alignment: .leading, spacing: 8) {
            Text("CPU Usage")
                .font(.headline)
                .foregroundStyle(.primary)
            
            HStack {
                Text("68%")
                    .font(.largeTitle.weight(.light))
                    .foregroundStyle(.blue)
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("8 Cores")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("3.2 GHz")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    .frame(maxWidth: 300, maxHeight: 150)
    .padding()
}
