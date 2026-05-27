import SwiftUI

enum AppTheme {
    static let panelPadding: CGFloat = 12
    static let panelCornerRadius: CGFloat = 12

    static let cpuColor: Color = .red
    static let ramColor: Color = .blue
    static let batteryColor: Color = .green
    static let networkColor: Color = .orange
    static let gpuColor: Color = .purple

    static let memoryUsedColor: Color = Color(red: 0.20, green: 0.58, blue: 0.94)
    static let memoryAppColor: Color = Color(red: 0.20, green: 0.58, blue: 0.94)
    static let memoryWiredColor: Color = Color(red: 0.56, green: 0.34, blue: 0.90)
    static let memoryCompressedColor: Color = Color(red: 0.99, green: 0.59, blue: 0.20)
    static let memoryCachedColor: Color = Color(red: 0.45, green: 0.78, blue: 0.39)
    static let memoryFreeColor: Color = Color(red: 0.72, green: 0.74, blue: 0.77)

    static let memoryPressureNormalColor: Color = Color(red: 0.19, green: 0.71, blue: 0.30)
    static let memoryPressureWarningColor: Color = Color(red: 0.99, green: 0.77, blue: 0.18)
    static let memoryPressureCriticalColor: Color = Color(red: 0.88, green: 0.24, blue: 0.25)

    static let batteryHealthGoodColor: Color = Color(red: 0.20, green: 0.75, blue: 0.29)
    static let batteryHealthWarningColor: Color = Color(red: 0.99, green: 0.77, blue: 0.18)
    static let batteryHealthCriticalColor: Color = Color(red: 0.86, green: 0.24, blue: 0.23)
}
