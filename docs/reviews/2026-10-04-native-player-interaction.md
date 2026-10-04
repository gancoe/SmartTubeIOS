# Native Apple TV player interaction

Date: 2026-10-04
Scope: personal `gancoe/SmartTubeIOS` fork, `native-tvos` branch.

## Changes

- Observe the active AVPlayer item across initial loading, fallback streams, quality changes and media-services reset. Ignore old item notifications and queued observer work after stopping.
- Show a five-second recommendation autoplay countdown on tvOS, with Play now, Cancel and Down to browse. Cancel pending autoplay when stopping, suspending or backgrounding with background playback disabled.
- Press Down from the video or bottom control row to browse recommendations; select a card to play it, or Back/Up to return. Cards load thumbnails without starting additional media players.
- Use the configured controls timeout on tvOS. Closing a picker restarts the timeout; Back immediately hides controls.
- Tie tvOS screensaver suppression to playback state across stream paths. Only the current playback owner can release that setting. Preserve existing explicit iOS idle-timer calls.

## Diagnosis evidence

The fallback paths lacked a consistent idle-timer update, while the main loading path explicitly disabled it. The alternative that a stopped player was releasing another active player's setting was found during review and addressed with ownership checked on the main actor. Physical screensaver causality remains UNVERIFIED until the new build is exercised on the Apple TV.

The controls timer regression was reproduced by closing a picker after its timer had been cancelled. A test failed before the restart fix and passed afterward. A separate end-observer test reproduced queued rebinding after stop and passed after adding an observer generation guard.

## Validation

- Focused native unit checks: 140 tests across 14 suites passed. Source: `tmp/native-player-unit-final.log`.
- Screensaver policy coverage: five tests cover playing/paused, natural end, looping, replacement ownership and stale teardown release. Source: `PlaybackIdleTimerTests.swift` in the focused run.
- Secrets, documentation links and strict formatting passed. `just ci` stops at 141 lint violations, including existing complexity and file-length problems in the large player files. The new Swift files have no reported lint violations. Source: `tmp/native-player-ci-final.log`.
- Independent review found no remaining correctness defect after the queued end-observer and idle-timer ownership fixes.
- An initial eight-check UI run passed five checks; three failed on native styled-button `hasFocus` assertions. Replacing those with actual remote actions and holding fixture expiry produced three passing reproductions with zero failures or skips. Source: `tmp/native-player-button-actions-summary.json`.
- `just test-native-tvos` passed: 140 focused unit tests across 14 suites and 16 simulator UI tests, zero failures and zero skips. The UI run includes eight Settings checks and eight native player interaction checks. Source: `tmp/native-tvos-tests.lPZbGx/settings.json` and its xcresult bundle; combined log: `tmp/native-player-focused-final.log`.
- Separate queue-exhaustion autoplay checks passed two tests. Source: `tmp/native-player-queue-final.log`.

The UI fixture hosts the actual PlayerView and remote handlers with deterministic videos and no media loading. The end-of-video UI fixture holds its timer to test remote actions without automatic expiry; a manual-clock unit test covers production countdown expiry. Native styled buttons are checked through Select outcomes rather than the simulator accessibility focus flag. These checks establish interaction and state transitions; they do not establish real YouTube decoding, full browse-screen navigation or physical screensaver behaviour.

The broader repository gate has inherited lint and unit-test problems documented in [the playback review](2026-10-04-native-playback.md). The focused native check does not replace that gate.
