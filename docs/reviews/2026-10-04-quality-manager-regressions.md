# Quality-manager regression coverage

Date: 4 October 2026. Scope: test-only follow-up on `test/quality-manager-regressions`, based directly on prepared revision `bba26b388571ead4932551c076a6d9c9e6f2788d`. The cache correction remains on its own branch.

## Purpose

The recovery audit identified player-item and rate checks that exercised local mirror types rather than `PlaybackQualityManager`. A buffer check asserted a local literal and described all HLS startup paths as equivalent. The production quality-switch path starts with a 2-second buffer; the initial fallback path uses 0.5 seconds. These are different contracts and must not be changed to satisfy a stale test description.

Replace the selected mirrors with tests using the existing `PlayerItemSwappable` and `QualityDelegate` seams. Capture the item created by the real manager and observe the real readiness path. No application interface or playback behaviour change is approved for this pass.

Six local-mirror/literal declarations were removed: item replacement, rate assignment, startup buffer, reset delay, post-reset buffer and asset-header-key equality. Seven real-manager tests now cover one replacement call (including nil-call detection), master-playlist preservation, requested and native caps, Auto without a cap, Auto retaining a native cap, H.264-capped reload, selection through `selectFormat`, the quality-switch startup buffer and readiness forwarding of rate/requested position. The existing Core User-Agent check remains.

The readiness case supplies a generated silent WAV file to the manager's asset path and installs the resulting item in a muted local AVPlayer. It verifies the real status observer and 1.5x rate assignment, plus the unchanged requested position of 23 seconds in the delegate callback. It does not decode an HLS video or actually perform that seek. Other item-configuration tests capture the created item without installing it. AsyncStream event waits respond to cancellation; the suite has a one-minute limit and cleans up the manager, player and temporary file.

## Validation

Measured final grouped run: 125 tests in 12 suites passed without skips, including all seven new manager tests. Source: `tmp/quality-manager-focused-final.log`. Existing quality/persistence, source/policy/manifest, recovery, seeking, item-failure, prefetch and end-observer suites are included. Legacy quality tests still contain copied algorithms outside this replacement; the grouped count is not a claim that every old check exercises the application.

Measured sensitivity: temporarily omitting the real `reloadHLSItem` invocation made the requested-cap test fail with zero replacement calls/items. The original invocation was restored before the final grouped pass. Source: `tmp/quality-manager-operation-omission-red.log`. This is a test-quality check, not discovery of a production regression. Application source was not mutated.

The new file passes scoped SwiftLint with zero violations. Source: `tmp/quality-manager-new-scoped-lint.log`. Final `just ci` passes secrets, documentation links and formatting, then stops at 150 lint violations before its unit-test step. Source: `tmp/quality-manager-ci.log`. Restoring only the original legacy test file for a controlled lint comparison yields 148 violations; the shortened file resurfaces two existing file/type size warnings. Source: `tmp/quality-manager-baseline-lint-comparison.log`. The committed baseline records those size rules at 670/664 lines; current warnings report smaller 628/622 counts, still above the configured limit. No baseline update or rule suppression conceals this remaining debt.

Independent Terra review identified missing coverage for Auto retaining a native source cap. The seventh test addresses it; re-review found no remaining P1/P2 finding and verified unchanged runtime code. Parent `git diff --exit-code baseline/prepared-bba26b3 -- SmartTubeIOS/Sources SmartTubeApp scripts .swiftlint.baseline .swiftlint.yml justfile` passed. No simulator rerun or new IPA is claimed for this test-only change.

## Boundaries

Both existing unsigned IPA checksums were remeasured and remain unchanged. Source: `tmp/quality-test-artifact-preservation.json`. No TV wake, connection, installation or playback action is part of this pass. A new IPA is unnecessary when only tests and review documents change.

These tests cannot establish sustained YouTube playback, network delivery, decoded resolution or Siri Remote behaviour. The physical comparison of prepared A and cache candidate B remains separate. Other copied algorithms and literal checks in the legacy quality suite are outside this bounded replacement unless explicitly recorded in the final diff.
