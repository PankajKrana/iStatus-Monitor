import SwiftUI

/// A reusable glass morphism card component with blur and depth effects.
/// Follows Apple's Glassmorphism aesthetic with Material backgrounds.
struct GlassCard<Content: View>: View {
    let content: Content
    var material: Material = .thin
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 12
    
    init(
        material: Material = .thin,
        padding: CGFloat = 16,
        cornerRadius: CGFloat = 12,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.material = material
        self.padding = padding
        self.cornerRadius = cornerRadius
    }
    
    var body: some View {
        content
            .padding(padding)
            .background(material)
            .cornerRadius(cornerRadius)
            .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 2)
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
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(.blue)
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("8 Cores")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("3.2 GHz")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    .frame(maxWidth: 300, maxHeight: 150)
    .padding()
}
