import Charts
import SwiftUI

struct BatteryView: View {
    let snapshot: BatterySnapshot

    private var healthColor: Color {
        if snapshot.healthPercent > 80 { return AppTheme.batteryHealthGoodColor }
        if snapshot.healthPercent > 50 { return AppTheme.batteryHealthWarningColor }
        return AppTheme.batteryHealthCriticalColor
    }

    private var batterySymbol: String {
        if snapshot.chargeState == .charging || snapshot.chargeState == .full {
            return "battery.100.bolt"
        }

        let clamped = max(0, min(100, Int(snapshot.chargePercent.rounded())))
        switch clamped {
        case 0 ..< 15: return "battery.0"
        case 15 ..< 40: return "battery.25"
        case 40 ..< 65: return "battery.50"
        case 65 ..< 90: return "battery.75"
        default: return "battery.100"
        }
    }

    private var estimatedCyclesTo80: Int {
        guard snapshot.healthPercent > 80, snapshot.cycleCount > 0 else { return 0 }
        let degradationPerCycle = (100.0 - snapshot.healthPercent) / Double(snapshot.cycleCount)
        guard degradationPerCycle > 0 else { return 0 }
        return Int(((snapshot.healthPercent - 80.0) / degradationPerCycle).rounded(.down))
    }

    private var timeRemainingText: String {
        switch snapshot.chargeState {
        case .charging:
            if let minutes = snapshot.timeToFullMinutes { return "To full: \(minutes)m" }
            return "To full: --"
        case .discharging:
            if let minutes = snapshot.timeToEmptyMinutes { return "To empty: \(minutes)m" }
            return "To empty: --"
        case .full:
            return "Fully charged"
        case .ac:
            return "On AC power"
        case .unknown:
            return "Unknown"
        }
    }
    
    private var chargeStatus: StatusBadge.Status {
        switch snapshot.chargeState {
        case .charging: return .charging
        case .discharging: return .discharging
        case .full: return .full
        case .ac: return .full
        case .unknown: return .custom("Unknown", .gray)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Hero Battery Ring
                GlassCard(material: .thin, padding: 16) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Battery Status")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Spacer()
                            StatusBadge(status: chargeStatus)
                        }

                        HStack(spacing: 20) {
                            CircularGauge(
                                value: snapshot.chargePercent,
                                color: AppTheme.batteryColor,
                                icon: "battery.50",
                                title: "Charge Level",
                                label: snapshot.chargeState.rawValue.capitalized,
                                strokeWidth: 10
                            )
                            .frame(width: 140, height: 160)

                            VStack(alignment: .leading, spacing: 12) {
                                MetricRowView(
                                    title: "Charge",
                                    value: String(format: "%.0f%%", snapshot.chargePercent),
                                    tint: AppTheme.batteryColor
                                )
                                
                                MetricRowView(
                                    title: "Health",
                                    value: String(format: "%.1f%%", snapshot.healthPercent),
                                    tint: AppTheme.batteryColor
                                )
                                
                                MetricRowView(
                                    title: "Cycle Count",
                                    value: "\(snapshot.cycleCount)",
                                    tint: AppTheme.batteryColor
                                )
                                
                                MetricRowView(
                                    title: "Temperature",
                                    value: String(format: "%.1f°C", snapshot.temperatureCelsius),
                                    tint: AppTheme.batteryColor
                                )
                            }
                            
                            Spacer()
                        }

                        HStack(spacing: 8) {
                            Text(timeRemainingText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("•")
                                .foregroundStyle(.secondary)
                            Text(snapshot.wattsString)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Health Section
                VStack(alignment: .leading, spacing: 10) {
                    Text("Battery Health")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    GlassCard(material: .thin) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Health Status")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(String(format: "%.1f%%", snapshot.healthPercent))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.primary)
                            }
                            ProgressView(value: snapshot.healthPercent, total: 100)
                                .tint(healthColor)

                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Cycles Until 80%")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(estimatedCyclesTo80) cycles")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.primary)
                                }
                                Text("Serial: \(snapshot.serialNumber)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                }

                // Charge History
                VStack(alignment: .leading, spacing: 10) {
                    Text("Charge History (24h)")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    GlassCard(material: .thin) {
                        Chart(snapshot.chargeHistory24h) { point in
                            LineMark(
                                x: .value("Time", point.timestamp),
                                y: .value("Charge", point.chargePercent)
                            )
                            .foregroundStyle(AppTheme.batteryColor)
                            .interpolationMethod(.catmullRom)
                        }
                        .frame(height: 120)
                        .chartYAxis(.hidden)
                    }
                }

                // Health Degradation
                VStack(alignment: .leading, spacing: 10) {
                    Text("Health Degradation")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    GlassCard(material: .thin) {
                        Chart(snapshot.healthHistory.suffix(40)) { point in
                            LineMark(
                                x: .value("Cycle", point.cycleCount),
                                y: .value("Health", point.healthPercent)
                            )
                            .foregroundStyle(healthColor)
                            .interpolationMethod(.linear)
                        }
                        .frame(height: 120)
                        .chartYAxis(.hidden)
                    }
                }
            }
        }
        .animation(AppTheme.springAnimation, value: snapshot)
    }
}

#Preview {
    BatteryView(
        snapshot: BatterySnapshot(
            timestamp: Date(),
            currentCapacitymAh: 4600,
            designCapacitymAh: 5200,
            healthPercent: 88.4,
            cycleCount: 302,
            chargeState: .charging,
            chargePercent: 67,
            timeToEmptyMinutes: 180,
            timeToFullMinutes: 46,
            voltageMillivolts: 12012,
            amperageMilliamps: 1800,
            watts: 21.6,
            temperatureCelsius: 34.2,
            temperatureFahrenheit: 93.6,
            serialNumber: "D86201ABC1",
            chargeHistory24h: (0 ..< 24).map { idx in
                BatteryChargePoint(timestamp: Date().addingTimeInterval(Double(-idx * 3600)), chargePercent: Double(40 + idx % 40))
            },
            healthHistory: (0 ..< 20).map { idx in
                BatteryHistoryPoint(timestamp: Date().addingTimeInterval(Double(-idx * 86400)), cycleCount: 200 + idx * 5, healthPercent: 95 - Double(idx) * 0.4)
            }
        )
    )
    .padding()
    .frame(width: 560)
}
