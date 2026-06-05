import SwiftUI

// MARK: - AppTheme
enum AppTheme {
    // MARK: Layout
    static let panelPadding: CGFloat = 12
    static let panelCornerRadius: CGFloat = 12
    static let sidebarWidth: CGFloat = 220
    
    // MARK: Semantic Colors - System Metrics
    static let cpuColor: Color = .orange           // CPU: Orange
    static let gpuColor: Color = .purple           // GPU: Purple
    static let ramColor: Color = .blue             // Memory: Blue
    static let diskColor: Color = .green           // Disk: Green
    static let networkColor: Color = .cyan         // Network: Cyan
    static let batteryColor: Color = .yellow       // Battery: Yellow
    static let temperatureColor: Color = .red      // Temperature: Red

    // MARK: Network Colors
    static let networkDownloadColor: Color = Color(red: 0.16, green: 0.61, blue: 0.98)
    static let networkUploadColor: Color = Color(red: 0.99, green: 0.53, blue: 0.22)

    // MARK: Memory Colors
    static let memoryUsedColor: Color = Color(red: 0.20, green: 0.58, blue: 0.94)
    static let memoryAppColor: Color = Color(red: 0.20, green: 0.58, blue: 0.94)
    static let memoryWiredColor: Color = Color(red: 0.56, green: 0.34, blue: 0.90)
    static let memoryCompressedColor: Color = Color(red: 0.99, green: 0.59, blue: 0.20)
    static let memoryCachedColor: Color = Color(red: 0.45, green: 0.78, blue: 0.39)
    static let memoryFreeColor: Color = Color(red: 0.72, green: 0.74, blue: 0.77)

    // MARK: Memory Pressure Status
    static let memoryPressureNormalColor: Color = Color(red: 0.19, green: 0.71, blue: 0.30)
    static let memoryPressureWarningColor: Color = Color(red: 0.99, green: 0.77, blue: 0.18)
    static let memoryPressureCriticalColor: Color = Color(red: 0.88, green: 0.24, blue: 0.25)

    // MARK: Battery Health Status
    static let batteryHealthGoodColor: Color = Color(red: 0.20, green: 0.75, blue: 0.29)
    static let batteryHealthWarningColor: Color = Color(red: 0.99, green: 0.77, blue: 0.18)
    static let batteryHealthCriticalColor: Color = Color(red: 0.86, green: 0.24, blue: 0.23)
    
    // MARK: Animation
    static let animationDuration: Double = 0.35
    static let springAnimation = Animation.spring(response: 0.4, dampingFraction: 0.75)
}
