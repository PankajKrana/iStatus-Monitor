import Charts
import SwiftUI

struct GPUView: View {
    let snapshot: GPUSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("GPU")
                .font(.headline)

            ForEach(snapshot.gpus) { gpu in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(gpu.name)
                                .font(.subheadline.weight(.semibold))
                            Text(gpu.vendor)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        ring(utilization: gpu.utilizationPercent)
                    }

                    if let total = gpu.vramTotalMB {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("VRAM")
                                Spacer()
                                Text(vramLabel(totalMB: total, usedMB: gpu.vramUsedMB))
                                    .monospacedDigit()
                            }
                            ProgressView(value: vramRatio(totalMB: total, usedMB: gpu.vramUsedMB), total: 1)
                                .tint(AppTheme.gpuColor)
                        }
                    } else if gpu.isIntegrated {
                        Text("Integrated GPU (shared memory on Apple Silicon / iGPU architecture)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 12) {
                        if let temp = gpu.temperatureCelsius {
                            Text(String(format: "%.1f °C", temp))
                        }
                        if let device = gpu.metalDeviceName {
                            Text(device)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        if let maxSet = gpu.recommendedMaxWorkingSetSize, maxSet > 0 {
                            Text("Max Set: \(Int(maxSet).toMemoryString())")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(Color.gray.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if !snapshot.displays.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Displays")
                        .font(.subheadline.weight(.semibold))

                    ForEach(snapshot.displays) { display in
                        HStack {
                            Text("Display \(display.id)")
                                .fontWeight(display.isMain ? .bold : .regular)
                            Spacer()
                            Text("\(display.width)×\(display.height)")
                                .monospacedDigit()
                            Text(refreshBadge(display.refreshRate))
                            if display.isRetina {
                                Text("Retina")
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                        }
                        .font(.caption)

                        Text(display.colorSpaceName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: snapshot)
    }

    private func ring(utilization: Double) -> some View {
        let active = max(0, min(utilization / 100, 1))
        return Chart {
            SectorMark(angle: .value("Used", active), innerRadius: .ratio(0.65), angularInset: 1)
                .foregroundStyle(AppTheme.gpuColor)
            SectorMark(angle: .value("Idle", 1 - active), innerRadius: .ratio(0.65), angularInset: 1)
                .foregroundStyle(Color.gray.opacity(0.2))
        }
        .chartLegend(.hidden)
        .frame(width: 62, height: 62)
        .overlay {
            Text("\(Int(utilization))%")
                .font(.caption2.monospacedDigit())
        }
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
