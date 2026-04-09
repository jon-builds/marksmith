# Marksmith

macOS menu bar utility that monitors the clipboard, detects Markdown content, converts it to rich text (HTML + RTF), and writes it back so pasting renders formatted text in any app.

Swift · SwiftUI · macOS 13+ · `swift-markdown` (SPM) · XcodeGen · Bundle ID: `com.jonathancheung.Marksmith`

## Workflow Rules

> **Before every commit**: review and update this file to reflect any changes to architecture, file structure, test counts, commands, gotchas, or implementation status. CLAUDE.md is the source of truth for the project — it must never be stale.

> **Before every release commit**: bump `MARKETING_VERSION` + `CURRENT_PROJECT_VERSION` in `project.yml`, and update "Current version" below.

**Current version**: 1.2.2 (build 5)

**Versioning convention** (single source of truth: `project.yml`):

Two independent fields in `project.yml`:

| Field | Current | Meaning |
|---|---|---|
| `MARKETING_VERSION` | `1.2.2` | User-visible version shown in About window and App Store |
| `CURRENT_PROJECT_VERSION` | `5` | Build number — monotonically increasing integer, never resets |

**When to bump what:**

| Release type | `MARKETING_VERSION` | `CURRENT_PROJECT_VERSION` | Example |
|---|---|---|---|
| Bug fix | Increment patch | +1 | 1.2.2 → 1.2.3, build 6 |
| New feature | Increment minor, reset patch | +1 | 1.2.2 → 1.3.0, build 6 |
| Major / monetization | Increment major, reset minor+patch | +1 | 1.2.2 → 2.0.0, build 6 |
| Beta / hotfix build | No change | +1 | 1.2.2 build 5 → 1.2.2 build 6 |

**Rules:**
- `CURRENT_PROJECT_VERSION` always increments for every release build — never resets, never repeats
- `MARKETING_VERSION` follows [Semantic Versioning](https://semver.org): MAJOR.MINOR.PATCH
- Both fields live only in `project.yml` — never hardcode versions elsewhere
- Update "Current version" line above whenever either field changes

**Bump checklist (before every release commit):**
1. Edit `project.yml` → increment `MARKETING_VERSION` and/or `CURRENT_PROJECT_VERSION`
2. Update `**Current version**` line in this file
3. Regenerate project: `xcodegen generate`
4. Verify version appears correctly in About window after build

## Prerequisites

- Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Commands

| Command | Description |
|---------|-------------|
| `xcodegen generate` | Generate `.xcodeproj` from `project.yml` |
| `xcodebuild build -project Marksmith.xcodeproj -scheme Marksmith` | Build the app |
| `xcodebuild test -project Marksmith.xcodeproj -scheme Marksmith` | Run all 86 unit tests |
| `xcodebuild test -only-testing:MarksmithTests/MarkdownDetectorTests` | Run a single test class |
| `./Scripts/build-release.sh` | Build and package unsigned DMG |
| `SIGN=1 ./Scripts/build-release.sh` | Build signed DMG (requires Developer ID) |
| `SIGN=1 NOTARIZE=1 ./Scripts/build-release.sh` | Build signed + notarized DMG |

## Architecture

```
Marksmith/
├── Marksmith/
│   ├── App/           # MarksmithApp.swift (@main), AppDelegate, AppState
│   ├── Views/         # MenuBarView (dropdown), SettingsView (General + Detection + Support tabs), AboutView
│   ├── Services/      # ClipboardMonitor, MarkdownDetector, MarkdownConverter, ClipboardWriter
│   ├── Utilities/     # Constants, PasteboardTypes (marker extension)
│   └── Resources/     # Assets.xcassets, Info.plist
├── MarksmithTests/  # 77 tests: detector (31), converter (27), writer (12), performance (5)
├── Scripts/             # build-release.sh, ExportOptions.plist, generate-icon.swift, generate-menubar-icon.swift
├── docs/                # PLAN.md, QA.md
└── project.yml          # XcodeGen configuration
```

**Data flow**: Timer (0.5s) → changeCount changed? → marker absent? → no existing HTML/RTF? → extract plain text → not empty, ≤100KB? → detect Markdown (score >= threshold) → convert (AST → HTML + RTF) → write back with marker → update conversion count

## Key Files

- `App/MarksmithApp.swift` — `@main` entry point, `MenuBarExtra` + `Settings` scenes
- `App/AppState.swift` — `@MainActor` singleton with `@AppStorage` preferences, `SMAppService` login item management
- `App/AppDelegate.swift` — Creates and manages `ClipboardMonitor` lifecycle
- `Services/ClipboardMonitor.swift` — Timer-based polling with guard pipeline, `hasSemanticHTML()` to skip rich clipboard from browsers while allowing code editor HTML, `[weak self]` timer, `.common` RunLoop mode, optional `UNUserNotificationCenter` conversion notifications
- `Services/MarkdownDetector.swift` — 15 pre-compiled `NSRegularExpression` patterns with weighted scoring, `.anchorsMatchLines` for `^`/`$` anchors
- `Services/MarkdownConverter.swift` — `HTMLVisitor` conforming to `MarkupVisitor` (22 visit methods), CSS styling, configurable `fontSize` parameter, RTF via `NSAttributedString` with heading paragraph style injection for Word/Pages compatibility
- `Services/ClipboardWriter.swift` — Multi-format `NSPasteboardItem` write with self-marker
- `Views/MenuBarView.swift` — Toggle, conversion status, Send Feedback, Settings button, quit with keyboard shortcuts
- `Views/SettingsView.swift` — Sidebar navigation with General (enable, login, RTF, notifications, font size), Detection (sensitivity slider), and Support (Buy Me a Coffee, Report a Bug, Request a Feature links) tabs
- `Utilities/PasteboardTypes.swift` — `NSPasteboard.PasteboardType.markdownPasteMarker` extension
- `Utilities/Constants.swift` — `pollingInterval` (0.5s), `maxContentSize` (100KB), `defaultDetectionThreshold` (2), `feedbackEmail`, `githubIssuesURL`, `githubRepoURL`

**Planned (v2.0)** — these files do not exist yet:
- `Models/LicenseState.swift` — `LicenseState` enum: `.trial(daysRemaining:)`, `.expired`, `.licensed` with computed `canConvert` and `statusText`
- `Services/LicenseManager.swift` — `@MainActor class`: trial tracking (first launch date), license key validation via API, offline caching
- `Views/LicenseSettingsView.swift` — Settings License tab: trial status, key entry, validation feedback, buy link

## Interface Contracts

```swift
// AppState — @MainActor singleton, consumed by all layers
@MainActor
class AppState: ObservableObject {
    static let shared = AppState()
    @AppStorage("isEnabled") var isEnabled: Bool                        // true
    @AppStorage("launchAtLogin") var launchAtLogin: Bool                // false
    @AppStorage("detectionSensitivity") var detectionSensitivity: Int   // 2
    @AppStorage("includeRTF") var includeRTF: Bool                     // true
    @AppStorage("showNotifications") var showNotifications: Bool        // false
    @AppStorage("baseFontSize") var baseFontSize: Int                  // 14
    @Published var conversionCount: Int                                 // 0
    @Published var lastConversionDate: Date?                            // nil
}

// Detector — stateless, pre-compiled regexes in init()
struct MarkdownDetector {
    func detect(text: String, threshold: Int) -> Bool
    func score(text: String) -> Int
}

// Converter — uses swift-markdown AST + HTMLVisitor
struct MarkdownConverter {
    func convert(markdown: String, fontSize: Int = 14) -> (html: String, rtf: Data?)
}

// Writer — always includes marker type
struct ClipboardWriter {
    func write(plainText: String, html: String, rtf: Data?)
}

// Monitor — owns detector, converter, writer; uses [weak self] timer
@MainActor
class ClipboardMonitor {
    init(appState: AppState)
    func start()
    func stop()
}
```

**Planned contracts (v2.0)** — not yet implemented:
```swift
// LicenseState — value type, computed by LicenseManager
enum LicenseState: Equatable {
    case trial(daysRemaining: Int)
    case expired
    case licensed
    var canConvert: Bool   // true for .trial and .licensed, false for .expired
    var statusText: String // "Trial: X days left", "Trial Expired", "Licensed"
}

// LicenseManager — @MainActor, owns trial/license logic
@MainActor
class LicenseManager: ObservableObject {
    init(appState: AppState)
    var currentState: LicenseState
    func validateLicenseKey(_ key: String) async -> LicenseValidationResult
    func deactivateLicense()
}

// AppState additions for licensing
@AppStorage("firstLaunchDate") var firstLaunchDate: Double      // 0
@AppStorage("licenseKey") var licenseKey: String                 // ""
@AppStorage("licenseValidatedAt") var licenseValidatedAt: Double // 0
@Published var licenseState: LicenseState                        // .trial(daysRemaining: 14)

// Constants additions for licensing
static let trialDurationDays: Int              // 14
static let purchaseURL: String                 // LemonSqueezy checkout URL
static let licenseValidationURL: String        // LemonSqueezy API URL
static let productID: String                   // LemonSqueezy product ID
static let licenseValidationTimeout: TimeInterval // 15
```

## Code Style

- Swift naming conventions (camelCase properties, PascalCase types)
- `struct` for stateless services (Detector, Converter, Writer); `class` for stateful (AppState, Monitor)
- `@MainActor` on `AppState` for SwiftUI thread safety
- `@AppStorage` for persisted user preferences; `@Published` for runtime-only state
- Prefer `guard` for early returns in pipeline methods
- Pre-compile `NSRegularExpression` patterns as stored properties in `init()`, not per-call
- Use `.anchorsMatchLines` option for regex patterns that use `^` or `$` anchors
- Use `@Environment(\.openSettings)` (macOS 14+) + `NSApplication.shared.activate()` for the Settings button — this both opens and raises the window. `SettingsLink` does not activate the app and fails to raise an already-open window in menu bar–only apps (`LSUIElement = true`). `NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)` is unreliable in SwiftUI; `SettingsLink` uses an internal SwiftUI mechanism, not that selector. Fall back to `SettingsLink` on macOS 13.

## SwiftUI Layout

- Settings tab views need `.padding(N).frame(maxWidth: .infinity, alignment: .leading)` on their outer VStack — `@ViewBuilder` bodies don't auto-stretch views to fill proposed width
- Order matters: `.padding(24).frame(maxWidth: .infinity)` is correct (frame receives full width, padding subtracts insets); reversed would add overflow
- All `Setting*Row` components use the same HStack pattern: icon (28×28) → `VStack(title+description)` → `Spacer()` → control (Toggle / Picker / etc.)

## Gotchas

- **No clipboard notification API on macOS** — must poll with `Timer`; 0.5s is the sweet spot for responsiveness vs CPU
- **Infinite loop risk** — writing to pasteboard triggers changeCount bump; always write the marker type and check for it before processing
- **Sandbox disabled** — `NSPasteboard.general` requires unsandboxed access; app is distributed via DMG, not App Store
- **macOS 16+ privacy prompts** — `NSPasteboardUsageDescription` in Info.plist provides the rationale; handle `nil` pasteboard reads gracefully
- **RTF generation must happen on main thread** — `NSAttributedString(html:documentAttributes:)` uses WebKit internally; Timer fires on main RunLoop so this is satisfied
- **Content size guard** — skip clipboard content > 100KB to avoid blocking the main thread
- **Detection false positives** — single `*` or `-` in plain text can score; threshold default of 2 requires multiple pattern matches
- **Operator precedence with Optional Bool** — `!optional?.contains(...) ?? true` has wrong precedence; use `optional?.contains(...) != true` instead
- **Timer RunLoop mode** — must add timer to `.common` mode via `RunLoop.current.add(timer!, forMode: .common)` so it fires even while menus are open
- **`@MainActor` access from Timer** — Timer callback runs on main thread but isn't annotated `@MainActor`; use `Task { @MainActor in ... }` for AppState mutations
- **Contact email lives in multiple places** — `Constants.swift` (`feedbackEmail`), `SECURITY.md`, and GitHub release notes (`gh release view <tag>`). Update all when changing email.
- **Word/Pages heading styles** — `NSAttributedString(html:) → RTF` loses semantic heading info (produces bold+size, not paragraph styles). RTF is post-processed to inject `\sN` stylesheet entries and paragraph markers. HTML headings include `mso-style-name` for Word's HTML import path. Both fixes needed since Word ignores plain `<h1>` tags in both formats.
- **Pages ignores NSPasteboardItem** — Apple Pages (and possibly other Apple apps) do not read RTF/HTML written via `NSPasteboardItem` + `writeObjects()`. Must use `declareTypes(_:owner:)` + `setString/setData` instead. Discovered via user testing — no Apple documentation explains this behavior.
- **Pasteboard type ordering** — `declareTypes` treats the first type as "most preferred". RTF must come before plain text so Pages/Word prefer rich text over raw markdown. Order: `.rtf` → `.html` → `.string` → `.markdownPasteMarker`.

## Testing

86 tests across 4 test files:

- `MarkdownDetectorTests` (31 tests) — positive (all GFM patterns), negative (plain text, URLs, emails), edge cases (empty, whitespace, threshold boundary, score capping, zero threshold)
- `MarkdownConverterTests` (38 tests) — all GFM elements produce correct HTML tags, RTF data is non-nil, HTML entities escaped, CSS styling present, full document structure, XSS prevention in code blocks and raw HTML, RTF heading style injection (stylesheet + paragraph markers), Word/Pages mso-style-name compatibility
- `ClipboardWriterTests` (12 tests) — all pasteboard types written, RTF conditional, marker always present, content integrity, clearing old content
- `MarkdownPerformanceTests` (5 tests) — detector and converter timing with typical and large fixtures, size guard assertion

**Planned tests (v2.0)** — 2 additional test files when monetization lands:
- `LicenseStateTests` (~12 tests) — canConvert, isExpired, statusText for each state (.trial, .expired, .licensed)
- `LicenseManagerTests` (~15 tests) — trial computation, state transitions, API validation (mock URLProtocol)

## Distribution Strategy

**Current (v1.2.2)**: Unsigned DMG via GitHub Releases. Recipients bypass Gatekeeper via System Settings → Privacy & Security → Security → Open Anyway on first launch.

**Future (v2.0)**: Source-available under FSL (Functional Source License, converts to MIT after 2 years). Signed+notarized DMG via Apple Developer Program. 14-day free trial with full lockout on expiry. One-time lifetime unlock ($9-15 USD) via LemonSqueezy/Gumroad — web checkout → license key → API validation → local cache.

## Implementation Status

Milestones 1–11 are complete (plus M10 automated portions). See `docs/PLAN.md` for remaining tasks:
- ~~**Milestone 7**: Build verification~~ ✓ (77 tests passing)
- ~~**Milestone 8**: Manual QA testing~~ ✓
- ~~**Milestone 9**: App icon design~~ ✓ (app icon + custom M↓ menu bar icon)
- ~~**Milestone 10**: Performance profiling~~ ✓ (automated; Instruments skipped)
- ~~**Milestone 11**: GitHub repository setup~~ ✓ (CI, LICENSE, templates, Dependabot)
- ~~**Milestone 12**: Unsigned DMG distribution + GitHub Release~~ ✓ (v1.0.0 released)
- ~~**Milestone 13**: About window~~ ✓ (v1.1.0 — `AboutView.swift`, `Window` scene, menu bar entry)
- ~~**Milestone 13.5**: Early feedback release~~ ✓ (v1.2.0 — feedback links in menu bar, Settings, About window)
- **Milestone 14**: Monetization — free trial + lifetime unlock (v2.0) — **design complete**, implementation after QA
