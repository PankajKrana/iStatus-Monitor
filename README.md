# iStatus Monitor

macOS 14+ system monitor built with Swift 6.2, SwiftUI lifecycle, and Swift Concurrency.

## Structure

- `iStatus Monitor/iStatus Monitor/Features/`
  - `CPU/`
  - `RAM/`
  - `Battery/`
  - `Network/`
  - `GPU/`
  - `MenuBar/`
- `iStatus Monitor/iStatus Monitor/Core/`
  - `MonitorService` (`SystemMonitorService` actor)
  - `DataStore` actor
  - `AlertEngine` actor
- `iStatus Monitor/iStatus Monitor/UI/`
  - `Charts/`
  - `Components/`
  - `Theme/`
- `iStatus Monitor/iStatus Monitor/Resources/`

## Architecture (ASCII)

```text
+----------------------+         +-----------------------+
|      SwiftUI App     |         |      MenuBarExtra     |
| iStatus_MonitorApp   |         |      MenuBarView      |
+----------+-----------+         +-----------+-----------+
           |                                 |
           v                                 |
+----------------------+                     |
|   @Observable        |<--------------------+
|      AppState        |
+----------+-----------+
           ^
           |
+----------+-----------------------------------------------+
|              SystemMonitorService (actor)                |
|  - runs async sampling loop                              |
|  - gathers CPU/RAM/Battery/Network/GPU concurrently      |
|  - updates AppState on MainActor                         |
|  - persists snapshots + triggers alerts                  |
+----------+-------------------------+---------------------+
           |                         |
           v                         v
+----------------------+   +----------------------+
|   Feature Monitors   |   |   Core Side Effects  |
|  CPUMonitor actor    |   |   DataStore actor    |
|  RAMMonitor actor    |   |   AlertEngine actor  |
|  BatteryMonitor ...  |   +----------------------+
|  NetworkMonitor ...  |
|  GPUMonitor ...      |
+----------------------+
```

## Configuration Notes

- Deployment target: macOS 14+
- Swift language mode: Swift 6.2
- No AppDelegate used; app uses SwiftUI lifecycle.
- Entitlements include sandbox disabled and network client/server enabled.
- `Info.plist` includes local network and notification-related keys.
- IOKit does not require a dedicated privacy key; this template includes `IStatusIOKitAccessReason` for internal documentation.
