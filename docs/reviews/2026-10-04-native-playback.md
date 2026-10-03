# Native Apple TV playback review, 4 October 2026

Scope: playback, seeking and SponsorBlock in the personal `native-tvos` fork.
Changes use the existing AVPlayer path and preserve the default constructor;
tests can inject a controlled AVPlayer without live YouTube requests.

## Test-first fixes

| Behaviour | Measured failure before the fix | Result after the fix |
|---|---|---|
| Automatic outro skip while AVPlayer duration is unavailable | Playback-end callback absent; ordinary seek left in progress | Falls back to known video duration and ends playback |
| Manual outro skip while AVPlayer duration is unavailable | Seeks to 29.5 seconds rather than handling playback end | Uses the same finite-duration fallback |
| Cancelled older seek finishes after the newest seek | Current position becomes 80 instead of 120 seconds | Only the latest successful completion updates position |
| Change video with a relative seek pending | New video receives a 120-second seek instead of 10 seconds | Load invalidates the old request and target |
| Stop with a relative seek pending | Next request is 120 instead of 110 seconds | Stop clears the pending target and invalidates completions |

The SponsorBlock RED logs are `tmp/review-sponsor-pending-red.log` and
`tmp/review-sponsor-manual-red.log`. Reproducible seek RED commands were:

```sh
just test-unit-filter PlaybackSeekingTests/staleCompletionDoesNotOverwriteLatestPosition
just test-unit-filter PlaybackSeekingTests/loadingAnotherVideoClearsPendingSeekTarget
just test-unit-filter PlaybackSeekingTests/stoppingClearsPendingSeekTarget
```

Those tests were run against the intermediate implementations before their
corresponding fixes. They now pass. The tests also exercise accumulated rapid
relative seeks, failed latest seeks, seek limits, unknown duration and retained
play/pause state. The bounded implementation worker repeated the seven-test
seeking suite ten times, with ten successful runs.

## Measured validation

- Final focused native unit run: 104 tests across eight suites passed.
  Source: `tmp/review-native-unit-final.log`.
- Settings simulator run: eight passed, zero failed and zero skipped.
  Source: `tmp/native-tvos-tests.Z0SjBz/settings.json` and its xcresult bundle.
- `just test-native-tvos` passed its initial combined run: 103 focused unit tests
  and eight Settings tests. One additional failed-latest-seek regression was
  added after that unit compilation, then the final 104-test run passed.
- Broader Home/focus simulator run: five passed, one failed and eight skipped.
  Source: `tmp/review-tvos-navigation.xcresult`. Missing feed cards prevented
  the skipped video/player tests from executing.
- Independent review found no remaining defect in the changed seeking,
  SponsorBlock and focused-check code.
- Secrets, documentation links and strict Swift formatting passed in `just ci`.
  The full gate still stops at 137 inherited lint violations.
  Source: `tmp/review-final-ci.log`; pristine upstream comparison is recorded in
  `tmp/upstream-lint.json`. The wider unit suite also has stale expectations,
  shared-state failures and a captured index-out-of-range crash whose cause
  remains UNVERIFIED. Source: `tmp/review-unit-baseline.log`.

Repeat the focused check with:

```sh
just test-native-tvos
```

It rejects zero tests, failures and skipped tests. It saves logs and an xcresult
bundle under a new `tmp/native-tvos-tests.*` directory. It is a focused check,
not a replacement for the full repository quality gate.

## Remaining findings and limits

The Settings scroll/focus test failed again in its isolated reproduction:
`TVFocusChainUITests.testSettingsTabBarVisibleAfterScrollDownAndUp` reports
`Settings.isHittable == false`. The recorded frame shows the Settings tab
visibly present and selected. Root cause remains UNVERIFIED; the test does not
establish whether physical remote navigation is broken. Check actual tab
switching after scrolling, and compare the accessibility result, before
changing focus handling. Source: `tmp/review-tvos-settings-repro.xcresult` and
`tmp/review-tvos-settings-repro-frame-final.png`.

Source review also found that the AVPlayer seek path does not call
`WatchtimeTracker.recordSeek`, while the TOS path does. Watchtime checkpoints
can therefore include a skipped interval. Account/server impact remains
UNVERIFIED. The next test-first slice should capture outgoing watchtime ranges
through a fake transport before adding success-only seek reporting.

Simulator tests do not prove physical Siri Remote behaviour, YouTube stream
availability, VP9/AV1 decoding, 4K/HDR, advertisement removal, or Google history
credit. New regression coverage controls local AVPlayer completions and uses
a local unavailable file for pending-duration cases. No real OAuth token is
required. The review does not install an update on the physical television.
