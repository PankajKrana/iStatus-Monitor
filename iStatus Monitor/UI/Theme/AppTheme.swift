import SwiftUI


enum AppTheme {
    // MARK: Layout
    static let panelPadding: CGFloat = 12
    static let panelCornerRadius: CGFloat = 12
    static let sidebarWidth: CGFloat = 220
    
    // MARK: Semantic Colors - System Metrics
    static let cpuColor: Color = .orange
    static let gpuColor: Color = .purple
    static let ramColor: Color = .blue
    static let diskColor: Color = .green
    static let networkColor: Color = .cyan
    static let batteryColor: Color = .yellow
    static let temperatureColor: Color = .red      

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

    // MARK: Memory Pressure Status (semantic system colors — adapt to dark mode & accessibility)
    static let memoryPressureNormalColor: Color = .green
    static let memoryPressureWarningColor: Color = .yellow
    static let memoryPressureCriticalColor: Color = .red

    // MARK: Battery Health Status (semantic system colors — adapt to dark mode & accessibility)
    static let batteryHealthGoodColor: Color = .green
    static let batteryHealthWarningColor: Color = .yellow
    static let batteryHealthCriticalColor: Color = .red
    
    // MARK: Animation
    static let animationDuration: Double = 0.35
    static let springAnimation = Animation.spring(response: 0.4, dampingFraction: 0.75)
}
