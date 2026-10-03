# SmartTube — agent guide

Native Swift/SwiftUI YouTube client for iOS/iPadOS (17+), macOS Catalyst (14+) and tvOS (17+).
Package `SmartTubeIOS/` (targets `SmartTubeIOSCore` = Foundation-only models/API/stores,
`SmartTubeIOS` = SwiftUI views, view models, services) + Xcode project `SmartTubeApp/`
(iOS+Catalyst app, tvOS app, Share/Safari extensions, Download widget, UI-test targets).
Architecture map: docs/architecture.md · Glossary: CONTEXT.md · Decisions: docs/adr/ · Plan: docs/modernization/

## Commands (always via `just`; run `just` to list)
- `just ci` — secrets check + format check + lint + unit tests. Run before every commit.
- `just build` / `just build-tvos` — simulator builds, no signing needed.
- `just test-unit` / `just test-unit-filter <Name>` — Swift Testing package tests (no simulator).
- `just test-smoke` — hermetic UI smoke plan. `just test-ui` — live UI plan (needs signed-in simulator; 3 workers max, see docs/how-to/run-tests.md).
- `just format` — swift-format in place. `just lint` — SwiftLint against the committed baseline.

## Rules that differ from defaults
- Swift 6 strict concurrency everywhere. View models are `@MainActor @Observable`. No `ObservableObject`, `@Published`, Combine, `DispatchQueue`, completion handlers in new code.
- `SmartTubeIOSCore` must stay Foundation-only (no SwiftUI/UIKit/AVFoundation/WebKit). Put platform code in `SmartTubeIOS`.
- One definition per constant/identifier/threshold. Accessibility identifiers come from `AccessibilityID`; SF Symbols from `AppSymbol`; playback timeouts from `PlaybackTuning`.
- Wrap UIKit-only API in `#if os(iOS)`; provide AppKit/tvOS branches. Never nest `NavigationStack`s.
- Never hand-edit `project.pbxproj` (a hook blocks it). New Swift files under synchronized folders are picked up automatically; UI-test files must be added in Xcode.
- Tests: Swift Testing for unit tests; no `Task.sleep`, no live network, fakes at protocol seams. UI tests use `AccessibilityID` and `waitForExistence`, never `sleep`.
- Logging via `os.Logger` (subsystem `AppSubsystem`), never `print`.
- Commits: Conventional Commits with the task ID, e.g. `fix(player): … (#312)`.

## Gotchas
- The Simulator cannot decode VP9/AV1 and cannot run PiP; assert stream *selection* in tests, not decoding.
- WKWebView `evaluateJavaScript` has no user activation: PiP/fullscreen cannot be triggered from Swift.
- Authenticated InnerTube calls use the TVHTML5 client on youtubei.googleapis.com with a Bearer token and no API key; the WEB client rejects Bearer tokens. Never call `/oauth2/v3/userinfo` for account info (the TV OAuth client isn't Data-API-v3-enabled) — use `account/accounts` with the TVHTML5 context instead.
- The 16 GB build Mac stalls with > 3 parallel simulator clones; `just` hardcodes 3.
- Playback fallback code (`PlaybackViewModel+Fallback.swift`) is under active decomposition (WS4). Do not add branches there; add a `StreamSource`.
- The personal fork fixes the native-macOS compile blockers. `just ci` still fails inherited lint checks; full unit execution also has stale and shared-state failures. `just test-native-tvos` is the focused native check, not a full gate. See `docs/reviews/2026-10-04-native-playback.md` for measured results and limitations.

## Where things are
- Playback: docs/architecture.md#playback · Tests how-to: docs/how-to/run-tests.md · Device logs: docs/how-to/device-logs.md
- Tasks: tasks/README.md (open items) · Modernization program: docs/modernization/PLAN.md
