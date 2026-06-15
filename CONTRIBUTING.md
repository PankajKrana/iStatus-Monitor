# Contributing to iStatus Monitor

First off — thank you for taking the time to contribute! 🎉 iStatus Monitor is a
native macOS menu bar system monitor, and it gets better with every thoughtful
issue, fix, and feature. This guide explains how to get set up, how the project
is organized, and what we expect from contributions.

By participating, you agree to keep the project welcoming and respectful for
everyone.

---

## 📋 Table of Contents

- [Project Overview](#project-overview)
- [Getting Started](#getting-started)
- [Branch Workflow](#branch-workflow)
- [Creating a Feature Branch](#creating-a-feature-branch)
- [Commit Message Conventions](#commit-message-conventions)
- [Pull Request Process](#pull-request-process)
- [Coding Standards](#coding-standards)
- [Testing Requirements](#testing-requirements)
- [Issue Reporting Guidelines](#issue-reporting-guidelines)
- [Security Issues](#security-issues)

---

## Project Overview

iStatus Monitor is a lightweight, native macOS utility that surfaces real-time
hardware metrics (CPU, RAM, GPU, Network, SSD, Battery, Thermal) directly from
the menu bar. It is built with **SwiftUI**, **AppKit**, **SwiftData**, **IOKit**,
and **Swift Concurrency**.

The architecture is **single-source-of-truth and observation-driven**:

- One background loop — `SystemMonitorService` (an `actor`) — samples all
  hardware on a fixed interval. It is the *only* sampling loop in the app.
- It publishes snapshots to `AppState` (an `@Observable`, `@MainActor` model),
  the single source of truth for live data.
- Every UI surface (menu bar label, popover, dashboard) derives from `AppState`
  via Observation — **no per-view timers, no duplicated state**.
- Per-domain monitors and stores (`HistoryStore`, `AlertEngine`, `DataStore`)
  are `actor`s; state is applied on the `@MainActor`.

Please keep contributions aligned with this model. See the **Architecture
Overview** in the [README](README.md) for the full diagram.

### Repository layout

```text
iStatus Monitor/
├── Core/                 # AppState, SystemMonitorService, DataStore, HistoryStore, AlertEngine
├── Features/
│   ├── CPU · RAM · GPU · Network · Disk · Battery · Thermal · Process
│   └── MenuBar/          # MenuBarExtra scenes, WidgetManager, renderer, settings
├── UI/
│   ├── Navigation/       # Dashboard shell, Settings
│   ├── Components/        # Per-metric views
│   ├── Charts/           # Sparklines, rolling time-series
│   └── Theme/
└── Resources/            # Assets, entitlements, Info.plist, PrivacyInfo.xcprivacy
iStatus MonitorTests/     # Swift Testing suite
```

---

## Getting Started

### Prerequisites

| Requirement | Version |
| --- | --- |
| macOS | macOS 26 (Tahoe) or later |
| Xcode | Xcode 26 or later |
| Architecture | Apple Silicon (arm64) |

### Set up your environment

```bash
# 1. Fork the repo on GitHub, then clone your fork
git clone https://github.com/<your-username>/iStatus-Monitor.git
cd "iStatus-Monitor"

# 2. Add the upstream remote so you can stay in sync
git remote add upstream https://github.com/PankajKrana/iStatus-Monitor.git

# 3. Open in Xcode
open "iStatus Monitor.xcodeproj"
```

Build and run with **⌘R**. The app launches into the menu bar (no Dock icon).

---

## Branch Workflow

This project uses a **three-tier branching model**. `main` is protected and
updated only through reviewed pull requests.

```text
main          ← stable, release-ready. Tagged for releases (v1.0.0, …). Protected.
  ▲
  │ PR (release candidate, reviewed)
  │
develop       ← integration branch. All feature work merges here first.
  ▲
  │ PR (reviewed, CI green)
  │
feature/*     ← your work. One branch per feature/fix, branched from develop.
```

| Branch | Purpose | Who merges in |
| --- | --- | --- |
| `main` | Stable, released code. Each release is tagged here (`v*`). **Protected — no direct pushes.** | Maintainers, via PR from `develop`. |
| `develop` | Active integration branch. The default base for new work. | Contributors, via PR from `feature/*`. |
| `feature/*` | A single feature, fix, or chore. Short-lived. | You. |

**Rules of thumb:**

- Branch new work from **`develop`**, not `main`.
- Open pull requests **into `develop`** (maintainers promote `develop → main`
  for releases).
- Keep branches short-lived and focused on one logical change.
- Rebase or merge `develop` into your branch to resolve conflicts before review.

### Branch naming

Use a type prefix and a short, hyphenated description:

| Prefix | Use for |
| --- | --- |
| `feature/` | New functionality (e.g. `feature/disk-io-graph`) |
| `fix/` | Bug fixes (e.g. `fix/battery-time-remaining`) |
| `docs/` | Documentation-only changes |
| `refactor/` | Code restructuring with no behavior change |
| `test/` | Adding or improving tests |
| `chore/` | Tooling, CI, dependencies, housekeeping |

---

## Creating a Feature Branch

```bash
# 1. Make sure develop is current
git checkout develop
git pull upstream develop

# 2. Create your feature branch
git checkout -b feature/my-feature

# 3. Work, commit, and push to your fork
git push -u origin feature/my-feature
```

Then open a pull request from `feature/my-feature` → `develop`.

---

## Commit Message Conventions

We follow [**Conventional Commits**](https://www.conventionalcommits.org/).
This keeps history readable and makes changelogs easy to generate.

**Format:**

```text
<type>(<optional scope>): <short summary>

<optional body — what & why, wrapped at ~72 chars>

<optional footer — e.g. "Closes #123">
```

**Types:**

| Type | When to use |
| --- | --- |
| `feat` | A new feature |
| `fix` | A bug fix |
| `docs` | Documentation only |
| `style` | Formatting, no code-meaning change |
| `refactor` | Code change that neither fixes a bug nor adds a feature |
| `perf` | A performance improvement |
| `test` | Adding or correcting tests |
| `build` | Build system or xcodeproj changes |
| `ci` | CI/workflow changes |
| `chore` | Maintenance, tooling, deps |

**Examples:**

```text
feat(network): show per-interface throughput in the popover
fix(battery): correct time-remaining when discharging on Apple Silicon
docs(readme): add unsigned-DMG installation steps
test(alerts): cover sustained-condition triggering across ticks
ci(release): pin Xcode 26.5 for reproducible archive
```

**Guidelines:**

- Use the **imperative mood** ("add", not "added" / "adds").
- Keep the summary line **≤ 72 characters**; no trailing period.
- Explain **why** in the body when the change isn't self-evident.
- Reference issues in the footer (`Closes #42`, `Refs #42`).

---

## Pull Request Process

1. **Sync** your branch with the latest `develop` and resolve conflicts.
2. **Run the tests locally** and make sure they pass (see below).
3. **Open the PR into `develop`** with:
   - A clear title (Conventional Commit style is great here too).
   - A description of **what** changed and **why**.
   - Linked issues (`Closes #N`).
   - Screenshots or short clips for any UI change.
4. **CI must pass.** The [`macOS Build`](.github/workflows/macos-build.yml)
   workflow builds and tests every PR into `develop`/`main` on a `macos-26`
   runner. PRs are not merged with red CI.
5. **Address review feedback** by pushing follow-up commits (don't force-push
   away review history unless asked).
6. A maintainer merges once it's approved and green.

**A good PR is:**

- ✅ Focused on one logical change.
- ✅ Covered by tests where it makes sense.
- ✅ Consistent with the existing architecture and style.
- ✅ Documented (README/docs updated if behavior or setup changed).
- ❌ Not a mix of unrelated refactors, features, and formatting churn.

---

## Coding Standards

iStatus Monitor is **Swift 6 / Swift Concurrency** first. Please follow these
conventions:

### Language & concurrency

- **Respect actor isolation.** Monitors and stores are `actor`s; UI state lives
  on `AppState` (`@MainActor`). Don't reach across isolation boundaries with
  unsafe escapes unless there's a documented reason (and a comment explaining it).
- **One loop, one state.** Do not add per-view timers or duplicate the sampling
  loop. New metrics feed through `SystemMonitorService` → `AppState`.
- **Presentation derives from data.** Compute view state from `AppState` +
  configuration via Observation; don't cache or shadow it.
- Prefer `async`/`await` and structured concurrency over callbacks or manual
  `DispatchQueue` work.
- Avoid force-unwraps (`!`) and `try!` in non-test code. Model "no data yet" with
  optionals or `.empty` values, as the existing snapshots do.

### Style

- Follow Swift API Design Guidelines: clear, descriptive names; lowerCamelCase
  for properties/functions, UpperCamelCase for types.
- Match the **surrounding code** for formatting (indentation, brace style,
  spacing). The codebase uses Xcode's default formatting.
- Keep functions small and focused. Extract helpers rather than growing one
  method.
- Add doc comments (`///`) to public types and non-obvious logic. The existing
  files (e.g. `AppState`, `HistoryStore`) are a good model — explain the *why*.
- No dead code, no commented-out blocks left behind, no `print` debugging in
  committed code.

### Privacy & permissions

- iStatus Monitor reads telemetry **on-device only** and ships a
  [`PrivacyInfo.xcprivacy`](iStatus%20Monitor/Resources/PrivacyInfo.xcprivacy)
  manifest. If you use a new "required reason" API, **update the manifest** with
  the correct reason code.
- Don't add data collection, analytics, network calls home, or third-party SDKs
  without prior discussion in an issue.

---

## Testing Requirements

The project ships a [Swift Testing](https://developer.apple.com/documentation/testing)
suite under `iStatus MonitorTests/` covering the monitor service, CPU sampling,
the alert engine, menu bar widgets, metric formatting, and SwiftData history
persistence.

**Run the full suite:**

```bash
xcodebuild test \
  -project "iStatus Monitor.xcodeproj" \
  -scheme "iStatus Monitor" \
  -destination 'platform=macOS' \
  -parallel-testing-enabled NO
```

> Parallel testing is disabled because the monitor-service tests poll real
> SMC/IOKit hardware and contend when run concurrently — mirror that locally.

**Expectations:**

- ✅ **All tests must pass** before you open or update a PR.
- ✅ **Add tests for new logic** — especially sampling math, formatting,
  alert-rule evaluation, and persistence. UI-only tweaks may not need tests, but
  business logic does.
- ✅ Keep tests **deterministic**. Inject clocks/intervals (as `HistoryStore`
  and `AlertEngine` already allow) instead of relying on wall-clock timing.
- ✅ Don't assert on values that depend on the specific machine's hardware;
  test behavior and ranges, not exact readings.

CI runs this exact suite on every PR; a red suite blocks merge.

---

## Issue Reporting Guidelines

Found a bug or have an idea? Please open an issue — but search existing issues
first to avoid duplicates.

### Bug reports

Include:

1. **Summary** — one sentence describing the problem.
2. **Environment** — macOS version, Mac model (e.g. "M2 MacBook Air"), and
   iStatus Monitor version (from the release or commit).
3. **Steps to reproduce** — numbered, minimal, reliable.
4. **Expected vs. actual** behavior.
5. **Evidence** — screenshots, a screen recording, or relevant log output.
   Scrub anything personal (the Network module shows your public IP).

### Feature requests

Include:

1. **The problem** you're trying to solve (not just the proposed solution).
2. **Your proposed behavior**, and any alternatives you considered.
3. **Scope/impact** — does it fit the menu-bar-first, on-device, lightweight
   philosophy of the app?

> 💡 For substantial features, open an issue to align on approach **before**
> writing code — it saves everyone time.

---

## Security Issues

**Do not report security vulnerabilities through public GitHub issues.** Please
follow the private disclosure process in [`SECURITY.md`](SECURITY.md).

---

Thanks again for contributing to iStatus Monitor! If anything here is unclear,
open a discussion or a draft PR and we'll help you get unblocked. 🚀
