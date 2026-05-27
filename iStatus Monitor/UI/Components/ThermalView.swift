import SwiftUI

struct ThermalView: View {
    let snapshot: ThermalSnapshot

    private let zoneOrder: [ThermalZone] = [.cpu, .gpu, .battery, .heatsink, .ambient]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            thermalStateBanner

            if snapshot.fans.isEmpty {
                Text("No fans detected (common on fanless Apple Silicon models).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 16) {
                    ForEach(snapshot.fans) { fan in
                        fanGauge(fan)
                    }
                }
            }

            ForEach(zoneOrder, id: \.rawValue) { zone in
                let sensors = snapshot.sensors.filter { $0.zone == zone }
                if !sensors.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(zoneTitle(zone))
                            .font(.subheadline.weight(.semibold))

                        ForEach(sensors) { sensor in
                            HStack {
                                Text(sensor.name)
                                Spacer()
                                Text(String(format: "%.1f°C / %.1f°F", sensor.celsius, sensor.fahrenheit))
                                    .monospacedDigit()
                                    .foregroundStyle(sensorColor(sensor.celsius))
                            }
                            .font(.caption)
                        }
                    }
                }
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: snapshot)
    }

    private var thermalStateBanner: some View {
        HStack {
            Text("Thermal State")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text(thermalStateLabel(snapshot.thermalState))
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(thermalStateColor(snapshot.thermalState).opacity(0.16))
                .foregroundStyle(thermalStateColor(snapshot.thermalState))
                .clipShape(Capsule())
        }
    }

    private func fanGauge(_ fan: FanReading) -> some View {
        Gauge(value: fan.percentOfMax, in: 0 ... 100) {
            Text("Fan \(fan.index)")
                .font(.caption)
        } currentValueLabel: {
            Text("\(Int(fan.rpm)) RPM")
                .font(.caption2.monospacedDigit())
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(sensorColor((fan.percentOfMax / 100.0) * 100.0))
    }

    private func zoneTitle(_ zone: ThermalZone) -> String {
        switch zone {
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .battery: return "Battery"
        case .heatsink: return "Heatsink"
        case .ambient: return "Ambient"
        }
    }

    private func thermalStateLabel(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }

    private func thermalStateColor(_ state: ProcessInfo.ThermalState) -> Color {
        switch state {
        case .nominal: return .blue
        case .fair: return .yellow
        case .serious: return .orange
        case .critical: return .red
        @unknown default: return .gray
        }
    }

    private func sensorColor(_ celsius: Double) -> Color {
        if celsius < 50 { return .blue }
        if celsius < 75 { return .yellow }
        if celsius < 90 { return .orange }
        return .red
    }
}

#Preview {
    ThermalView(
        snapshot: ThermalSnapshot(
            timestamp: Date(),
            fans: [
                FanReading(index: 0, rpm: 2300, minRPM: 1200, maxRPM: 5600, percentOfMax: 41.0),
                FanReading(index: 1, rpm: 2600, minRPM: 1200, maxRPM: 5600, percentOfMax: 46.4)
            ],
            sensors: [
                ThermalSensor(key: "TC0P", name: "CPU", celsius: 67.4, fahrenheit: 153.3, zone: .cpu),
                ThermalSensor(key: "TG0D", name: "GPU", celsius: 58.2, fahrenheit: 136.8, zone: .gpu),
                ThermalSensor(key: "TA0P", name: "Ambient", celsius: 31.2, fahrenheit: 88.2, zone: .ambient)
            ],
            thermalState: .fair
        )
    )
    .padding()
}
