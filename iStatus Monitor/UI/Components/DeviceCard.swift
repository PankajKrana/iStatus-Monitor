import SwiftUI

/// A card for displaying device information with battery indicator.
struct DeviceCard: View {
    let name: String
    let icon: String
    let batteryPercent: Double?
    let isConnected: Bool
    let subtitle: String?
    
    var body: some View {
        GlassCard(material: .thin) {
            HStack(spacing: 12) {
                // Device icon
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.blue)
                    .frame(width: 40, height: 40)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                
                // Device info
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else if isConnected {
                        Text("Connected")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }
                
                Spacer()
                
                // Battery indicator
                if let batteryPercent = batteryPercent {
                    VStack(alignment: .trailing, spacing: 4) {
                        ZStack {
                            Circle()
                                .stroke(Color.gray.opacity(0.2), lineWidth: 2)
                            
                            Circle()
                                .trim(from: 0, to: batteryPercent / 100)
                                .stroke(batteryColor(batteryPercent), lineWidth: 2)
                                .rotationEffect(.degrees(-90))
                            
                            Text("\(Int(batteryPercent))")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.primary)
                        }
                        .frame(width: 36, height: 36)
                        
                        Text("Battery")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
    
    private func batteryColor(_ percent: Double) -> Color {
        if percent > 70 { return .green }
        if percent > 30 { return .orange }
        return .red
    }
}

#Preview {
    VStack(spacing: 12) {
        DeviceCard(
            name: "AirPods Pro",
            icon: "airpodspro",
            batteryPercent: 85,
            isConnected: true,
            subtitle: nil
        )
        
        DeviceCard(
            name: "Magic Mouse",
            icon: "computermouse.fill",
            batteryPercent: 45,
            isConnected: true,
            subtitle: "2.0"
        )
        
        DeviceCard(
            name: "Magic Keyboard",
            icon: "keyboard",
            batteryPercent: 12,
            isConnected: false,
            subtitle: nil
        )
    }
    .padding()
}
