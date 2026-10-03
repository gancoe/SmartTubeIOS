> status: current (2026-10-04)

# How to run tests

**When to use:** running unit or UI tests locally, or setting up a fresh simulator.

All commands are `just` recipes (run `just` from the repo root to list them). Don't use
`mcp_xcode_RunAllTests`/`mcp_xcode_RunSomeTests` or any other `mcp_xcode_*` tool to run tests.

## Target simulator

Single source of truth for the iOS/Catalyst target simulator — don't copy this UDID into other
docs, link here instead.

| Property | Value |
|---|---|
| Name | iPhone 17 |
| UDID | `6CEE2FAC-7D50-4BD0-95E2-1361EDD7FAF6` |
| OS | iOS 26.4.1 |

### One-time simulator setup

Disable the crash dialog so a mid-test crash doesn't block subsequent tests (persists across
reboots, reset if the simulator is erased):

```bash
xcrun simctl boot 6CEE2FAC-7D50-4BD0-95E2-1361EDD7FAF6 2>/dev/null; sleep 3
xcrun simctl spawn 6CEE2FAC-7D50-4BD0-95E2-1361EDD7FAF6 \
  defaults write com.apple.CrashReporter DialogType none
```

Verify: `xcrun simctl spawn 6CEE2FAC-7D50-4BD0-95E2-1361EDD7FAF6 defaults read com.apple.CrashReporter DialogType` should print `none`.

## Memory ceiling

16 GB Mac Mini. Each simulator clone adds ~500–750 MB RAM (copy-on-write). **3 workers is the
ceiling** — 5 stalls clone boot indefinitely with no output. `justfile` hardcodes 3; don't raise
it without more RAM.

## Commands

- `just test-unit` — Swift Testing package tests, no simulator.
- `just test-native-tvos` — focused native unit tests and tvOS Settings simulation,
  rejecting failures, empty runs and skips. See [native tvOS](native-tvos.md).
- `just test-ui-legacy` — UI tests, 3 parallel workers. Temporary until WS3-T3.4 adds the
  `Smoke`/`Live` test plans, at which point `just test-smoke`/`just test-ui` take over.
- `just test-ui-one <SmartTubeUITests/Suite/testMethod>` — a single UI test.
- Device/app log capture during a test run: `docs/how-to/device-logs.md`.

## Known quality limits

The personal fork fixes the native-macOS compile blockers. The full unit suite
still has stale expectations and shared-state failures, and `just ci` stops at
inherited lint violations. The focused native check does not establish a passing
full repository gate. See the [playback review](../reviews/2026-10-04-native-playback.md)
for measured results and remaining simulator/hardware limits.
