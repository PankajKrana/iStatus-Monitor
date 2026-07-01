import Charts
import SwiftUI

struct GPUView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let snapshot: GPUSnapshot

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(snapshot.gpus, id: \.id) { gpu in
                    GlassCard(material: .thin, padding: 16) {
                        VStack(alignment: .leading, spacing: 14) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(gpu.name)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(gpu.vendor)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            HStack(spacing: 20) {
                                CircularGauge(
                                    value: gpu.utilizationPercent,
                                    color: AppTheme.gpuColor,
                                    icon: "display",
                                    title: "GPU Utilization",
                                    label: "\(Int(gpu.utilizationPercent))%",
                                    strokeWidth: 10
                                )
                                .frame(width: 140, height: 160)

                                VStack(alignment: .leading, spacing: 12) {
                                    if let temp = gpu.temperatureCelsius {
                                        MetricRowView(
                                            title: "Temperature",
                                            value: String(format: "%.0f°C", temp),
                                            tint: AppTheme.gpuColor
                                        )
                                    }
                                    
                                    if let total = gpu.vramTotalMB {
                                        MetricRowView(
                                            title: "VRAM Total",
                                            value: String(Int(total).toMemoryString()),
                                            tint: AppTheme.gpuColor
                                        )
                                    }
                                    
                                    if let device = gpu.metalDeviceName {
                                        MetricRowView(
                                            title: "Device",
                                            value: device,
                                            tint: AppTheme.gpuColor
                                        )
                                    }
                                    
                                    if gpu.isIntegrated {
                                        Text("Integrated GPU")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                
                                Spacer()
                            }

                            if let total = gpu.vramTotalMB {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("VRAM Usage")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text(vramLabel(totalMB: total, usedMB: gpu.vramUsedMB))
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.primary)
                                    }
                                    ProgressView(value: vramRatio(totalMB: total, usedMB: gpu.vramUsedMB), total: 1)
                                        .tint(AppTheme.gpuColor)
                                }
                            }
                        }
                    }
                }

                if !snapshot.displays.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Displays")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        ForEach(snapshot.displays) { display in
                            GlassCard(material: .thin) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Display \(display.id)")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        
                                        HStack(spacing: 8) {
                                            Text("\(display.width)×\(display.height)")
                                                .font(.caption.monospacedDigit())
                                                .foregroundStyle(.secondary)
                                            
                                            Text(refreshBadge(display.refreshRate))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            
                                            if display.isRetina {
                                                StatusBadge(status: .custom("Retina", .blue))
                                            }
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(display.colorSpaceName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        
                                        if display.isMain {
                                            StatusDot(status: .good)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .animation(reduceMotion ? .none : AppTheme.springAnimation, value: snapshot)
    }

    private func vramRatio(totalMB: Int, usedMB: Int?) -> Double {
        guard totalMB > 0, let usedMB else { return 0 }
        return max(0, min(Double(usedMB) / Double(totalMB), 1))
    }

    private func vramLabel(totalMB: Int, usedMB: Int?) -> String {
        if let usedMB {
            return "\(usedMB) MB / \(totalMB) MB"
        }
        return "\(totalMB) MB"
    }

    private func refreshBadge(_ refresh: Double) -> String {
        if refresh <= 0.1 { return "-- Hz" }
        return String(format: "%.0f Hz", refresh)
    }
}

#Preview {
    GPUView(
        snapshot: GPUSnapshot(
            timestamp: Date(),
            gpus: [
                GPUStats(
                    id: "g0",
                    name: "Apple M3 Pro GPU",
                    vendor: "Apple",
                    utilizationPercent: 47,
                    vramTotalMB: nil,
                    vramUsedMB: nil,
                    temperatureCelsius: 46,
                    metalDeviceName: "Apple M3 Pro",
                    isLowPower: true,
                    isRemovable: false,
                    recommendedMaxWorkingSetSize: 12_000_000_000,
                    isIntegrated: true
                )
            ],
            displays: [
                DisplayInfo(id: 1, width: 3024, height: 1964, refreshRate: 120, isMain: true, isRetina: true, colorSpaceName: "Display P3")
            ]
        )
    )
    .padding()
}
