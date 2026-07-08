import SwiftUI

struct OnboardingSheet: View {
    /// Requests notification authorization in-context (HIG: ask at the moment of
    /// value). Injected so the sheet stays decoupled from the alerts store.
    var onRequestNotifications: () -> Void = {}

    @State private var currentPage: Int = 0
    @State private var animateSymbol: Bool = false
    @State private var notificationsRequested = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                page(
                    title: "Welcome to iStatus Monitor",
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
                ) {
                    Button {
                        onRequestNotifications()
                        notificationsRequested = true
                    } label: {
                        Label(
                            notificationsRequested ? "Notification Request Sent" : "Enable Notifications",
                            systemImage: notificationsRequested ? "checkmark.circle.fill" : "bell.fill"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(notificationsRequested)
                }
                .tag(1)

                page(
                    title: "Menu Bar Setup",
                    subtitle: "Use the menu bar widget for quick visibility without opening the app.",
                    symbol: "menubar.rectangle",
                    tint: .green
                )
                .tag(2)
            }

            HStack(spacing: 8) {
                ForEach(0 ..< 3, id: \.self) { index in
                    let isCurrent = index == currentPage
                    Circle()
                        .fill(isCurrent ? Color.accentColor : Color.secondary.opacity(0.35))
                        // Differentiate the current page by size as well as color,
                        // so the indicator is legible without relying on hue alone.
                        .frame(width: isCurrent ? 9 : 7, height: isCurrent ? 9 : 7)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Page \(currentPage + 1) of 3")
            .padding(.bottom, 8)

            HStack {
                if currentPage > 0 {
                    Button("Back") {
                        changePage(by: -1)
                    }
                }

                Spacer()

                if currentPage < 2 {
                    Button("Next") {
                        changePage(by: 1)
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
        // Fixed width for a stable card, but let height grow so larger Dynamic
        // Type / accessibility text sizes aren't clipped (HIG: accommodate all
        // text sizes).
        .frame(width: 620)
        .frame(minHeight: 430)
        .onAppear {
            animateSymbol = !reduceMotion
        }
    }

    private func page<Accessory: View>(
        title: String,
        subtitle: String,
        symbol: String,
        tint: Color,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) -> some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: symbol)
                .font(.system(size: 72, weight: .medium))
                .foregroundStyle(tint)
                .scaleEffect(animateSymbol ? 1.08 : 1)
                .symbolEffect(.pulse.byLayer, options: .repeating, isActive: animateSymbol && !reduceMotion)
                .animation(reduceMotion ? .none : .easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: animateSymbol)

            Text(title)
                .font(.title2.weight(.bold))

            Text(subtitle)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)

            accessory()

            Spacer()
        }
        .padding(24)
    }

    private func changePage(by delta: Int) {
        if reduceMotion {
            currentPage += delta
        } else {
            withAnimation(.snappy) {
                currentPage += delta
            }
        }
    }

    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        dismiss()
    }
}

#Preview {
    OnboardingSheet()
}
