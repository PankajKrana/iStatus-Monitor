# Release Readiness Report — iStatus Monitor v1.0.0

**Date:** 2026-06-15
**Branch:** `feature/v1.0.0-release-docs` (off `develop`)
**Scope:** Documentation & open-source readiness only. No application
functionality was modified. **The `v1.0.0` tag has _not_ been created.**

---

## Summary

| Area | Status |
| --- | --- |
| README links work | ✅ Pass |
| Screenshot paths correct | ✅ Pass (7/9 present, 2 intentionally pending) |
| CONTRIBUTING.md complete | ✅ Pass |
| SECURITY.md complete | ✅ Pass |
| Release notes complete | ✅ Pass |
| CI configuration valid | ✅ Pass |
| Release workflow valid | ✅ Pass |
| Privacy manifest exists | ✅ Pass |
| Release blockers | ✅ None (1 optional follow-up) |

**Verdict:** 🟢 **Ready to tag v1.0.0** once (optionally) the two remaining
screenshots are captured. Nothing below is a hard blocker.

---

## Deliverables produced

| File | Description |
| --- | --- |
| `README.md` | Reworked screenshots section (5 showcase screens), local image paths, CI/CD badges, expanded feature list (Alerts & History), CI/CD table, improved unsigned-DMG install steps, links to new docs. |
| `CONTRIBUTING.md` | New. Branch model (`main`/`develop`/`feature/*`), feature-branch how-to, Conventional Commits, PR process, coding standards, testing requirements, issue guidelines. |
| `SECURITY.md` | New. Supported versions, private reporting, coordinated disclosure, security scope (in/out), response process. |
| `RELEASE_NOTES_v1.0.0.md` | New. Overview, major features, architecture, modules, widgets, alerts, history, CI/CD, known limitations, roadmap. |
| `docs/images/` | New directory. 7 screenshots migrated from GitHub user-attachments to versioned local assets + a capture guide (`docs/images/README.md`). |

---

## Detailed audit

### 1. README links — ✅ Pass
- All **local** references resolve on disk: `CONTRIBUTING.md`, `SECURITY.md`,
  `RELEASE_NOTES_v1.0.0.md`, `LICENSE`, both workflow files, `docs/images/` and
  every image. Verified by existence check.
- The `#-license` self-anchor was replaced with a direct link to `LICENSE`.
- External links are well-formed (shields.io badges, apple.com, swift.org,
  GitHub repo/releases/actions). Actions badge + workflow URLs follow GitHub's
  canonical pattern for `PankajKrana/iStatus-Monitor`.

### 2. Screenshot paths — ✅ Pass
- Migrated 7 images out of ephemeral `user-attachments` URLs into
  `docs/images/` (validated as real PNGs, HTTP 200 on download).
- **Zero** `user-attachments` references remain in the README.
- Showcase sections present: **Dashboard, Menu Bar, Alerts, History, Settings.**
- `alerts.png` and `history.png` are **not yet captured**; their `<img>` tags are
  enclosed in HTML comments, so **no broken images render**. They are documented
  in the capture guide with exact filenames and ready-to-uncomment slots.

### 3. CONTRIBUTING.md — ✅ Pass
- All 10 table-of-contents anchors match generated heading slugs (verified).
- Covers every required topic: project overview, three-tier branch workflow,
  feature-branch creation, commit conventions, PR process, coding standards,
  testing requirements, issue reporting, and security cross-link.

### 4. SECURITY.md — ✅ Pass
- Supported versions table, private reporting (GitHub advisories + fallback),
  disclosure timeline (90-day coordinated), explicit in/out-of-scope (notably the
  known unsigned/unsandboxed states are declared out of scope), and a numbered
  response process.

### 5. Release notes — ✅ Pass
- All requested sections present and consistent with the actual codebase
  (verified against `AppState`, `SystemMonitorService`, `AlertEngine`,
  `HistoryStore`, `AlertModels`, `WidgetRegistry`).

### 6. CI configuration (`macos-build.yml`) — ✅ Pass
- Valid YAML. Triggers: push→`develop`, PR→`develop`/`main`. Runner `macos-26`,
  Xcode 26.5 pinned with fallback. Build + full test suite, least-privilege
  `contents: read`. Does **not** run on tags.

### 7. Release workflow (`release.yml`) — ✅ Pass
- Valid YAML. Trigger: `v*` tags only. Flow test→archive→DMG→publish, with a
  `create-dmg` path and `hdiutil` fallback. `contents: write`, per-tag
  concurrency, `fail_on_unmatched_files: true`. No overlap with CI.

### 8. Privacy manifest — ✅ Pass
- `iStatus Monitor/Resources/PrivacyInfo.xcprivacy` present and well-formed:
  `NSPrivacyTracking=false`, no collected data types, no tracking domains, and
  documented required-reason API codes (UserDefaults `CA92.1`, DiskSpace
  `85F4.1`, SystemBootTime `35F9.1`). Entitlements and `Info.plist`
  (`LSUIElement`, usage strings) also present.

---

## Non-blocking follow-ups

1. **(Optional) Capture `alerts.png` and `history.png`** and uncomment the two
   slots in the README to complete the gallery. Steps are in
   `docs/images/README.md`. Not a blocker — the README renders cleanly without
   them.
2. **Version metadata:** `MARKETING_VERSION = 1.0` in the project. Consider
   bumping to `1.0.0` for cosmetic consistency with the tag (cosmetic only;
   `v1.0.0` tag will drive the release artifact name regardless).
3. **Signing/notarization** remains intentionally deferred (hooks stubbed in
   `release.yml`); documented as a known limitation, not a blocker.

---

## Next step (when ready — not performed here)

```bash
# After this branch is reviewed & merged develop → main:
git checkout main && git pull
git tag v1.0.0
git push origin v1.0.0   # triggers release.yml → builds & publishes the DMG
```
