# Security Policy

iStatus Monitor takes the security and privacy of its users seriously. This
document explains which versions receive security fixes, how to report a
vulnerability privately, and what to expect after you do.

---

## Supported Versions

iStatus Monitor follows [Semantic Versioning](https://semver.org/). Security
fixes are applied to the latest release line. Older lines are supported on a
best-effort basis until the next minor release supersedes them.

| Version | Supported |
| --- | --- |
| `1.0.x` | ✅ Actively supported |
| `< 1.0` | ❌ Pre-release; not supported |

Because the app distributes as a downloadable `.dmg`, **security fixes ship as a
new tagged release** — there is no auto-update channel yet. Always run the most
recent release from the [Releases](https://github.com/PankajKrana/iStatus-Monitor/releases)
page.

---

## Reporting a Vulnerability

**Please do not report security vulnerabilities through public GitHub issues,
pull requests, or discussions.** Public disclosure before a fix is available
puts users at risk.

Instead, use one of these private channels:

1. **GitHub Private Vulnerability Reporting (preferred).**
   Go to the repository's **Security** tab → **Report a vulnerability**, or open
   <https://github.com/PankajKrana/iStatus-Monitor/security/advisories/new>.
   This creates a private advisory visible only to you and the maintainers.

2. **Direct contact.** If you cannot use GitHub's private reporting, open a
   minimal public issue titled "Security contact request" (with **no technical
   detail**) asking a maintainer to reach out, and we will establish a private
   channel.

### What to include

A good report helps us triage quickly. Please include as much as you can:

- A clear description of the vulnerability and its **impact**.
- The **affected version(s)** and your environment (macOS version, Mac model).
- **Step-by-step reproduction** instructions or a proof of concept.
- Any relevant logs, screenshots, or crash reports (scrub personal data such as
  your public IP, which the Network module displays).
- Your assessment of severity, if you have one.

---

## Disclosure Expectations

We follow a **coordinated disclosure** model:

- Please give us a reasonable opportunity to investigate and release a fix
  **before** any public disclosure.
- We aim to resolve confirmed vulnerabilities and publish a fixed release within
  **90 days** of confirmation, and usually much sooner for high-severity issues.
- Once a fix is released, we will publish a security advisory and credit the
  reporter (unless you prefer to remain anonymous).
- Please **do not** exploit a vulnerability beyond what is necessary to
  demonstrate it, access or modify other users' data, or degrade the service.

We support good-faith security research. We will not pursue or support legal
action against researchers who follow this policy.

---

## Scope

iStatus Monitor is a **local, on-device** macOS application. It reads hardware
telemetry locally and does not collect, transmit, or track user or device data,
and it bundles no third-party SDKs (see
[`PrivacyInfo.xcprivacy`](iStatus%20Monitor/Resources/PrivacyInfo.xcprivacy)).
Keep this in mind when assessing impact.

### In scope

- Memory-safety or privilege issues in the app's use of **IOKit / SMC / sysctl**
  hardware-reading code.
- Improper handling of the app's **entitlements** (the app runs **unsandboxed**
  with network client/server entitlements) that could be abused.
- Local privilege escalation or arbitrary code execution via the app or its
  **Launch-at-Login** (`SMAppService`) integration.
- Insecure storage or leakage of data the app persists locally via **SwiftData**
  / `UserDefaults` (e.g. alert rules, history, configuration).
- Vulnerabilities in the **release pipeline** that could allow a tampered DMG to
  be published.
- Exposure of sensitive local data (e.g. **public IP**, active connections,
  process names) beyond the user's own machine.

### Out of scope

- **Lack of code signing / notarization.** This is a known, documented state —
  builds are currently **unsigned** because no Apple Developer ID is configured.
  The Gatekeeper warning and the manual "Open Anyway" step are expected; see the
  README installation section. (Adding signing is on the roadmap.)
- The app intentionally running **unsandboxed** and **without a Dock icon**
  (`LSUIElement`) — these are design decisions required to read hardware metrics.
- Issues that require an already-compromised machine, physical access, or root
  privileges the attacker would already need to obtain elsewhere.
- Vulnerabilities in macOS, Xcode, GitHub Actions runners, or other third-party
  infrastructure (report those to the respective vendors).
- Social-engineering, phishing, or denial-of-service against GitHub itself.
- Reports generated solely by automated scanners with no demonstrated impact.

---

## Response Process

After you submit a report, here is what happens:

1. **Acknowledgement** — we aim to acknowledge your report within **3 business
   days**.
2. **Triage** — we confirm the issue, determine affected versions, and assign a
   severity. We may ask follow-up questions through the private advisory.
3. **Fix** — we develop and test a fix on a private branch.
4. **Release** — we publish a new tagged release containing the fix and update
   the supported-versions table.
5. **Disclosure** — we publish a security advisory describing the issue and the
   fix, crediting you unless you ask otherwise.

Thank you for helping keep iStatus Monitor and its users safe. 🔐
