# Screenshot & Image Assets

This directory holds the image assets referenced by the project [`README.md`](../../README.md).
Keep filenames stable — the README links to them by exact path, and the release
audit verifies those paths.

## Recommended showcase screens

The five screens below tell the product story end to end. Capture them on a Mac
running macOS 26 (Tahoe) in **both** light and dark mode if possible, then keep
the variant that reads best against GitHub's default (light) theme.

| File | Screen | What it should show | Status |
| --- | --- | --- | --- |
| `dashboard.png` | **Dashboard** | The full on-demand window with CPU, RAM, GPU, Network, SSD, Battery, and Thermal cards populated with live data. | ✅ present |
| `menubar-compact.png` | **Menu Bar** | The compact combined status item in the menu bar showing several live metrics at a glance. | ✅ present |
| `module-cpu-memory.png` | **Menu Bar — CPU & Memory popover** | A per-module popover with detailed CPU/Memory readouts. | ✅ present |
| `module-network.png` | **Menu Bar — Network popover** | A per-module popover with up/down throughput and interface detail. | ✅ present |
| `module-battery-thermal.png` | **Menu Bar — Battery & Thermal popover** | A per-module popover with charge, health, and thermal/fan detail. | ✅ present |
| `alerts.png` | **Alerts** | The Alerts screen: at least one rule configured (e.g. "CPU > 90% for 30s") plus a few fired entries in the alert history. | ⬜ to capture |
| `history.png` | **History** | The History screen with a time-series chart/sparkline showing a metric trending over time. | ⬜ to capture |
| `settings.png` | **Settings** | The Settings window (General + menu bar widget configuration). | ✅ present |
| `app-icon.png` | App icon | The 1024×1024 app icon, used as the README title glyph. | ✅ present |

## Capture guidelines

- **Resolution:** capture on a Retina display; export at 2× (the README scales
  with explicit `width` attributes, so high-DPI sources stay crisp).
- **Format:** PNG, trimmed to the relevant window/popover with a little padding.
- **Privacy:** scrub anything personal before publishing — the Network module
  surfaces your **public IP** and active connections; the Process insights list
  shows running app names. Blur or use a clean test session.
- **Consistency:** use the same wallpaper/accent across shots so the gallery
  feels cohesive.

## Adding the two remaining shots

`alerts.png` and `history.png` are the only screens not yet captured. To finish
the README gallery:

1. Run the app, open **Dashboard**, and navigate to the **Alerts** tab. Add a
   rule and let it fire once (or lower a threshold so it triggers), then capture
   `alerts.png`.
2. Switch to the **History** tab, let a few minutes of data accumulate so a
   trend is visible, then capture `history.png`.
3. Drop both files into this directory using the exact names above. The README
   already has the gallery slots wired up.
