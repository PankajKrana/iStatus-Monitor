# iStatus Monitor v1.0.0 — Release Notes

**The first stable release of iStatus Monitor.** 🎉

iStatus Monitor is a native macOS menu bar system monitor that keeps a real-time
pulse on your Mac's hardware — CPU, RAM, GPU, Network, SSD, Battery, and
Thermal — without ever getting in your way. It lives in the menu bar, runs
quietly in the background, and opens a full dashboard only when you want it.

> **Requirements:** macOS 26 (Tahoe) or later, Apple Silicon (arm64).

---

## Overview

iStatus Monitor is built entirely with **SwiftUI**, **AppKit**, **SwiftData**,
**IOKit**, and **Swift Concurrency**. It favors a modern, observation-driven
architecture: a single monitoring loop feeds one observable state model, and
every view — menu bar label, popover, and dashboard — derives from that single
source of truth. The result is a lightweight agent app (no Dock icon) that's
accurate, responsive, and easy on resources.

---

## Major Features

- **Full hardware coverage** — CPU, Memory, GPU, Network, SSD/Disk, Battery, and
  Thermal, all live.
- **Menu-bar-first experience** — compact combined item *or* one item per metric,
  each with a detail popover. No Dock icon (`LSUIElement` agent app).
- **On-demand dashboard** — a full window you can open from any popover and close
  without quitting; monitoring keeps running.
- **Color-coded severity** — menu bar labels shift color (normal / warning /
  critical) as values change.
- **Threshold alerts** — per-metric rules with sustained-condition triggering and
  native notifications.
- **Local history** — metrics persisted with SwiftData and charted as rolling
  sparklines.
- **Launch at Login** — via the modern `SMAppService` API.
- **Fully customizable** — reorder widgets, choose display styles, pick layouts.
- **Private by design** — all telemetry is read on-device; no tracking, no
  data collection, no third-party SDKs.

---

## Architecture Highlights

iStatus Monitor uses a **single-source-of-truth, observation-driven** design:

- **One loop, one state.** `SystemMonitorService` (an `actor`) is the sole
  sampling loop. It owns no UI; the UI owns no timers. Each tick samples all
  domains and publishes a snapshot.
- **`AppState` is the single source of truth.** An `@Observable`, `@MainActor`
  model holds live metrics. Because it's observation-based, SwiftUI re-renders
  only the views that read a changed property.
- **Concurrency-safe by construction.** Per-domain monitors and the stores
  (`HistoryStore`, `AlertEngine`, `DataStore`) are `actor`s; state is applied on
  the `@MainActor`.
- **Presentation derives from data.** `WidgetManager` computes menu bar segments
  from `AppState` + configuration via Observation — nothing is cached or
  duplicated.
- **Explicit lifecycle.** As an agent app, the process outlives its windows
  (`applicationShouldTerminateAfterLastWindowClosed → false`); monitoring is tied
  to app lifetime, not the dashboard window.

```text
iStatus_MonitorApp  →  WindowGroup (Dashboard) · MenuBarExtra · Settings
                                   │
                          AppState (@Observable, @MainActor)   ◄── single source of truth
                                   ▲
                       SystemMonitorService (actor)            ◄── the only loop
                ┌──────────┬───────┼───────┬──────────┐
              CPU · Memory · Network · GPU · Battery · …        ◄── per-domain monitors
                                   │
                  DataStore · HistoryStore (SwiftData) · AlertEngine
```

---

## Monitoring Modules

| Module | What it reports |
| --- | --- |
| **CPU** | Overall load, per-core usage, load averages, frequency (Intel), temperature |
| **Memory (RAM)** | Used / free / wired / compressed / cached, swap, app footprint |
| **GPU** | Utilization, VRAM, temperature |
| **Network** | Real-time up/down throughput, interface details, local & public IP |
| **SSD / Disk** | Capacity, used/free space, read/write speeds |
| **Battery** | Charge, health, cycle count, time remaining, temperature |
| **Thermal** | Sensor readings, fan RPM, thermal pressure state |
| **Process insights** | Top CPU- and memory-consuming processes |
| **Network insights** | Active connections, top network processes, public IP |

---

## Menu Bar Widgets

- **Compact mode** — a single combined status item rendering all enabled metrics
  in one place.
- **Per-module mode** — one independent menu bar item per metric, each
  individually toggleable, each with its own detail popover.
- **Live, color-coded labels** — values shift color with severity.
- **Customizable widgets** — reorder, pick display styles, and choose layouts via
  the `WidgetManager` / `WidgetRegistry` configuration, persisted across launches.

---

## Alerting System

- **Per-metric rules** for CPU, Memory, Temperature, Battery, and Network, each
  with its own threshold and unit.
- **Severity levels** — info / warning / critical, derived from how far a value
  exceeds its threshold and used for color, glyph, and sorting.
- **Sustained triggering** — a rule can require its condition to hold for *N*
  seconds before firing, suppressing transient spikes. Per-rule timers ensure
  multiple rules (even multiple CPU rules) never share a counter.
- **Native notifications** — delivered through the `UserNotifications` framework
  as banners, with an in-app alert history.
- **Live history updates** — the alert history refreshes as alerts fire, backed
  by the `AlertEngine` actor.

---

## History Tracking

- **SwiftData persistence** — sampled metrics are written to a local store via
  the `HistoryStore` `@ModelActor`, throttled to a configurable persist interval
  (default 10s) so the database stays compact.
- **Per-metric series** — CPU, memory, network throughput, and battery are
  recorded over time.
- **Rolling charts** — the History view renders the stored series as sparklines /
  rolling time-series so you can see a trend, not just the current value.

---

## CI/CD Automation

Two non-overlapping GitHub Actions workflows, both on `macos-26` runners with the
Xcode 26 toolchain:

- **`macos-build.yml` (CI).** Runs on pushes to `develop` and on pull requests
  into `develop` / `main`. Builds the app and runs the full Swift Testing suite
  (parallel testing disabled because the monitor tests poll real hardware).
  Never runs on tags.
- **`release.yml` (CD).** Runs **only** on a pushed `v*` tag. Flow:
  `tag → test (Debug) → archive (Release) → build DMG → publish GitHub Release`.
  Produces `iStatus-Monitor-<tag>.dmg` (with an Applications drag-link) and
  attaches it to an auto-generated GitHub Release. Uses least-privilege
  permissions and per-tag concurrency so a half-uploaded asset is never left
  behind.

The test suite covers the monitor service, CPU sampling, the alert engine, menu
bar widgets, metric formatting, and SwiftData history persistence.

---

## Known Limitations

- **Unsigned / not notarized.** Builds ship **without** an Apple Developer ID, so
  Gatekeeper blocks the first launch. Use right-click → **Open** (or **Open
  Anyway** in Privacy & Security) once. The release pipeline already has signing
  and notarization hooks stubbed in for when a certificate is available.
- **macOS 26 (Tahoe) and Apple Silicon only.** The app targets the macOS 26 SDK
  and arm64. Some metrics that rely on Intel-only sysctls (e.g. nominal CPU
  frequency) are gracefully omitted on M-series Macs.
- **No in-app auto-update.** Updates are delivered as new releases on the GitHub
  Releases page; there is no Sparkle-style updater yet.
- **DMG-only distribution.** Not currently on the Mac App Store or Homebrew Cask.
- **Some sensor coverage is hardware-dependent.** Fan RPM, certain temperatures,
  and GPU VRAM detail vary by Mac model and may be unavailable on some machines.

---

## Future Roadmap

Planned and under consideration for future releases (not commitments):

- 🔏 **Code signing + notarization** to remove the Gatekeeper friction.
- 🔄 **In-app updates** (e.g. Sparkle) and/or a **Homebrew Cask**.
- 📊 **Richer history** — longer retention, exportable data, more chart types.
- 🔔 **More alert conditions** — additional metrics and compound rules.
- 🌐 **Localization** beyond the development region.
- 🧩 **More menu bar widget styles** and layout options.
- 🖥️ **Broader hardware coverage** as Apple exposes more sensors.

---

## Acknowledgements

Thank you to everyone who tested early builds and filed issues. Contributions are
welcome — see [`CONTRIBUTING.md`](CONTRIBUTING.md). Found a security issue? See
[`SECURITY.md`](SECURITY.md).

**Full project details:** [README.md](README.md) ·
**License:** [MIT](LICENSE)
