import SwiftUI

struct OnboardingSheet: View {
    @State private var currentPage: Int = 0
    @State private var animateSymbol: Bool = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                page(
                    title: "Welcome to PulseKit",
                    subtitle: "Real-time monitoring for CPU, Memory, Network, GPU, Thermal, and Battery.",
                    symbol: "waveform.path.ecg.rectangle",
                    tint: .blue
                )
                .tag(0)

                page(
                    title: "Enable Notifications",
                    subtitle: "Allow notifications to receive warning and critical alerts.",
                    symbol: "bell.badge.fill",
                    tint: .orange
                )
                .tag(1)

                page(
                    title: "Menu Bar Setup",
                    subtitle: "Use the menu bar widget for quick visibility without opening the app.",
                    symbol: "menubar.rectangle",
                    tint: .green
                )
                .tag(2)
            }

            HStack(spacing: 6) {
                ForEach(0 ..< 3, id: \.self) { index in
                    Circle()
                        .fill(index == currentPage ? Color.accentColor : Color.secondary.opacity(0.35))
                        .frame(width: 7, height: 7)
                }
            }
            .padding(.bottom, 8)

            HStack {
                if currentPage > 0 {
                    Button("Back") {
                        withAnimation(.snappy) {
                            currentPage -= 1
                        }
                    }
                }

                Spacer()

                if currentPage < 2 {
                    Button("Next") {
                        withAnimation(.snappy) {
                            currentPage += 1
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Get Started") {
                        completeOnboarding()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
            .background(.regularMaterial)
        }
        .frame(width: 620, height: 430)
        .onAppear {
            animateSymbol = true
        }
    }

    private func page(title: String, subtitle: String, symbol: String, tint: Color) -> some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: symbol)
                .font(.system(size: 72, weight: .medium))
                .foregroundStyle(tint)
                .scaleEffect(animateSymbol ? 1.08 : 0.92)
                .symbolEffect(.pulse.byLayer, options: .repeating, isActive: animateSymbol)
                .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: animateSymbol)

            Text(title)
                .font(.title2.weight(.bold))

            Text(subtitle)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)

            Spacer()
        }
        .padding(24)
    }

    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        dismiss()
    }
}

#Preview {
    OnboardingSheet()
}
