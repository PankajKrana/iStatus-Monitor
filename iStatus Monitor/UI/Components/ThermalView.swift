import SwiftUI

struct ThermalView: View {
    let snapshot: ThermalSnapshot

    private let zoneOrder: [ThermalZone] = [.cpu, .gpu, .battery, .heatsink, .ambient]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Thermal State Hero
                GlassCard(material: .thin, padding: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Thermal State")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Spacer()
                            StatusBadge(status: thermalStatusBadge(snapshot.thermalState))
                        }

                        Text(thermalStateDescription(snapshot.thermalState))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Fans Section
                if !snapshot.fans.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Fans")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(snapshot.fans) { fan in
                                GlassCard(material: .thin) {
                                    VStack(alignment: .center, spacing: 8) {
                                        Text("Fan \(fan.index)")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)

                                        ZStack {
                                            Circle()
                                                .stroke(Color.gray.opacity(0.2), lineWidth: 3)

                                            Circle()
                                                .trim(from: 0, to: min(fan.percentOfMax / 100.0, 1))
                                                .stroke(sensorColor((fan.percentOfMax / 100.0) * 100.0), lineWidth: 3)
                                                .rotationEffect(.degrees(-90))

                                            VStack(spacing: 2) {
                                                Text("\(Int(fan.rpm))")
                                                    .font(.title3.weight(.semibold))
                                                Text("RPM")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        .frame(height: 80)

                                        HStack(spacing: 4) {
                                            Text("\(Int(fan.minRPM))")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                            Spacer()
                                            Text("\(Int(fan.maxRPM))")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                } else {
                    GlassCard(material: .thin) {
                        Text("No fans detected (common on fanless Apple Silicon models).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Temperature Sensors by Zone
                ForEach(zoneOrder, id: \.rawValue) { zone in
                    let sensors = snapshot.sensors.filter { $0.zone == zone }
                    if !sensors.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(zoneTitle(zone))
                                .font(.headline)
                                .foregroundStyle(.primary)

                            ForEach(sensors) { sensor in
                                GlassCard(material: .thin) {
                                    HStack(alignment: .center, spacing: 12) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(sensor.name)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.primary)
                                            Text(sensor.key)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        HStack(spacing: 12, content: {
                                            VStack(alignment: .trailing, spacing: 2) {
                                                Text(String(format: "%.1f°C", sensor.celsius))
                                                    .font(.title3.weight(.semibold))
                                                Text(String(format: "%.1f°F", sensor.fahrenheit))
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }

                                            Circle()
                                                .fill(sensorColor(sensor.celsius))
                                                .frame(width: 12, height: 12)
                                                .shadow(color: sensorColor(sensor.celsius).opacity(0.5), radius: 4, x: 0, y: 2)
                                        })
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .animation(AppTheme.springAnimation, value: snapshot)
    }

    private func zoneTitle(_ zone: ThermalZone) -> String {
        switch zone {
        case .cpu: return "CPU Temperature"
        case .gpu: return "GPU Temperature"
        case .battery: return "Battery Temperature"
        case .heatsink: return "Heatsink Temperature"
        case .ambient: return "Ambient Temperature"
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

    private func thermalStateDescription(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "System operating normally"
        case .fair: return "System performing optimally"
        case .serious: return "System experiencing thermal stress"
        case .critical: return "System in critical thermal condition"
        @unknown default: return "Unknown thermal state"
        }
    }

    private func thermalStatusBadge(_ state: ProcessInfo.ThermalState) -> StatusBadge.Status {
        switch state {
        case .nominal: return .normal
        case .fair: return .normal
        case .serious: return .warning
        case .critical: return .critical
        @unknown default: return .custom(thermalStateLabel(state), .gray)
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
                ThermalSensor(key: "TC0P", name: "CPU Core", celsius: 67.4, fahrenheit: 153.3, zone: .cpu),
                ThermalSensor(key: "TG0D", name: "GPU Core", celsius: 58.2, fahrenheit: 136.8, zone: .gpu),
                ThermalSensor(key: "TA0P", name: "Ambient", celsius: 31.2, fahrenheit: 88.2, zone: .ambient)
            ],
            thermalState: .fair
        )
    )
    .padding()
}
