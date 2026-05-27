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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: batterySymbol)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(AppTheme.batteryColor)
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Battery")
                        .font(.headline)
                    Text(String(format: "%.0f%% • %@", snapshot.chargePercent, snapshot.chargeState.rawValue.capitalized))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(snapshot.wattsString)
                    .font(.title3.monospacedDigit())
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Health")
                    Spacer()
                    Text(String(format: "%.1f%%", snapshot.healthPercent))
                        .monospacedDigit()
                }
                ProgressView(value: snapshot.healthPercent, total: 100)
                    .tint(healthColor)
            }

            HStack(spacing: 14) {
                Text("Cycle Count: \(snapshot.cycleCount)")
                    .font(.subheadline.monospacedDigit())
                Text("To 80%: \(estimatedCyclesTo80) cycles")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 14) {
                Text(timeRemainingText)
                Text(snapshot.temperatureCString)
                Text(snapshot.temperatureFString)
                Text("Serial: \(snapshot.serialNumber)")
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Charge (24h)")
                    .font(.caption.weight(.semibold))

                Chart(snapshot.chargeHistory24h) { point in
                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Charge", point.chargePercent)
                    )
                    .foregroundStyle(AppTheme.batteryColor)
                    .interpolationMethod(.catmullRom)
                }
                .frame(height: 62)
                .chartYAxis(.hidden)
                .chartXAxis(.hidden)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Health Degradation")
                    .font(.caption.weight(.semibold))

                Chart(snapshot.healthHistory.suffix(40)) { point in
                    LineMark(
                        x: .value("Cycle", point.cycleCount),
                        y: .value("Health", point.healthPercent)
                    )
                    .foregroundStyle(healthColor)
                    .interpolationMethod(.linear)
                }
                .frame(height: 62)
                .chartYAxis(.hidden)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: snapshot)
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
