# Native source and recovery audit

Date: 4 October 2026. Status: test-only audit; runtime changes not approved.

## Scope and baseline

Jonathan approved a focused source/recovery audit and missing deterministic tests, with the prepared release kept fixed. Work is on `test/native-recovery-regressions`, starting from `baseline/prepared-bba26b3` at `bba26b388571ead4932551c076a6d9c9e6f2788d`.

Measured at the start: clean working tree, pinned source revision and saved IPA SHA256 verified. Prepared IPA checksum: `dea00ee011dcc93c1a9dc3edea86f85f20d6492fca78f2f14891acf574a4d4a3`. No TV contact, installation, signed release, playback-engine change or application source edit is part of this pass. Physical acceptance of A and actual native 4K playback remain pending.

Astra independently challenged the plan before approval. Its recommendation was to audit/test first and choose a production slice afterwards. A separate Terra review traced current source ownership during this pass.

## Ranked hypotheses and results

1. **Quality preference changes reclassify an already-ready item.** The production `configureHLSPlayback` invocation is in `attemptURL`, before item installation (`PlaybackViewModel+Fallback.swift:1175,1245`). A preference change itself does not reconfigure the installed stream policy. A direct mid-item `configureHLSPlayback` mutation would be an artificial scenario, not proof of a user-reachable defect. The new replay tests exercise preference changes through `settings.preferredQuality`.
2. **Recovery followed by same-video reopening loses observers.** `stop` invalidates failure/end observers; the parked-item `load` route calls `setupRateObserver`, which reinstalls them (`PlaybackViewModel+Loading.swift:78,1171`; `PlaybackViewModel+Observers.swift:54`). Existing parked-item and recovered-end tests cover those behaviours separately. The new test combines native failure, H.264 replacement and reopening, then verifies a later media-services reset remains observable. Its parked identity is injected to avoid WebView extraction; it is not a complete physical stop/prewarm test.
3. **A queued callback from an old item changes the replacement.** Current failure callbacks check player, item, video and observation generation (`PlaybackViewModel+ItemFailure.swift:30,64`); end callbacks check item and generation (`PlaybackViewModel+Observers.swift:169`). Existing stale-item and stop tests already cover this, so no duplicate test was added.

No reachable new defect in those three scenarios was verified by the source audit. Cache invalidation below is a separate confirmed mismatch, not evidence that these guards are wrong.

## Findings

### Cache invalidation misses source-policy entries

Filtered HLS variants are stored using `videoID|height|codecs` (`HLSPlaybackPolicy.swift:72`; `PlaybackViewModel+Fallback.swift:1018`). Quality 403 recovery calls `HLSManifestCache.shared.invalidate(for: video.id)` (`PlaybackViewModel.swift:657`); the cache removes only that exact key (`HLSManifestCache.swift:46`). Other recovery call sites use the same bare video ID (`PlaybackViewModel+Fallback.swift:1774,1791,1856,1872`).

Alternative checked: expiry might remove those entries instead. The reproducer stores fresh entries, uses no delay and invalidates immediately, so its failure cannot be explained by TTL expiry. Bare-key removal works while policy entries remain. This establishes the invalidation mismatch, not a network failure or decoder failure.

Impact: after a fresh filtered manifest fetch returns no variants, `attemptURL` can fall back to the old policy entry (`PlaybackViewModel+Fallback.swift:1023`). The filtered route still supplies the master URL to AVPlayer (`:1069`), so this audit does not claim it directly feeds an expired variant URL to decoding. Stale quality availability/selection metadata can survive the recovery. Whether this contributes to physical freezes is UNVERIFIED; a captured device recovery trace would settle that.

### Some quality tests do not exercise application code

`PlaybackQualityTests.swift:719` creates a local mirror, calls its own replacement method and asserts its own counter. `:732` sets and checks a local rate. `:747` asserts a local startup-buffer literal of 2 seconds, while the actual fallback currently sets 0.5 seconds (`PlaybackViewModel+Fallback.swift:1217`). These tests can pass despite a production change. They are evidence about the test fixture, not the player.

Do not count those passes as proof of real player behaviour. Replace selected mirrors with tests calling the real quality-manager/item seam in a separate follow-on; do not change buffering to match stale test literals.

### Existing baseline queue tests fail

The first unchanged-runtime baseline filter executed 109 tests across nine suites and reported two failures in `PlaybackEndAutoplayTests`. Source: `tmp/recovery-audit-baseline.log`. Existing source/recovery, seeking and end-observer checks passed in that run. The failing tests share `CurrentQueueStore.shared`, mutate it around awaits, and schedule unawaited cleanup; they also contain timed polling. Each failing method passed when run alone: `tmp/recovery-audit-queueExhaustionFallsThroughToRecommendations.log` and `tmp/recovery-audit-queueExhaustionWithNoFallbackEndsVideo.log`. This supports a test-isolation concern; the exact interleaving remains UNVERIFIED. It does not establish an autoplay failure in the app. Both grouped failures remain reported; no existing test was skipped, changed or weakened.

### Guidance points to missing roadmap files

`AGENTS.md` and `docs/architecture.md` refer to modernization/tasks documents absent from this checkout. Proposed ADR-0005 is not an implemented source pipeline. Accepted ADR-0008 intentionally retains unreachable Shorts infrastructure. Neither stale guidance nor apparent unreachable code justifies broad deletion.

## Validation and test changes

Measured this pass:

- Three new transition tests exercise the real view model through controlled player/item KVO. Worker run: `tmp/recovery-audit-transition-rerun.log`. Parent final grouped run: `tmp/recovery-audit-focused-final.log`, 60 tests in nine suites passed, no skips. The filter includes source/manifest policy, recovery, seeking, item failure, prefetch and end-observer suites; it does not represent the full repository gate.
- Sensitivity check: temporarily omitting the real `load(video:)` reopen action made the reopen test fail on missing later error observation. Original test restored, then the grouped pass verified it. Source: `tmp/recovery-audit-reopen-sensitivity-red.log`. No application mutation was used. The final test title explicitly states injected parked identity.
- Cache RED: one test failed with two expectations, proving the native and H.264 policy entries survive bare-ID invalidation. Source: `tmp/recovery-audit-cache-red.log`. Initial test compilation required correcting the Core test import; that compilation failure is separate and is not the bug evidence.
- New active test file: scoped SwiftLint reports zero violations. Source: `tmp/recovery-audit-scoped-lint.log`.
- `just ci` passes secrets, documentation links and formatting, then fails lint with 148 violations. Source: `tmp/recovery-audit-ci.log`. The recorded release review also reported 148; this is a failing full gate and unit execution in that gate was not reached. The lint baseline was not changed.
- Independent final review found one test-title overclaim about stop-generated parking; the title now names injected parked identity. The reviewer confirmed the test's WebView/network isolation and the report's limited cache-impact claim.

The deliberately failing cache test is [preserved as a separate reproducer](reproducers/HLSRecoveryCacheRegressionTests.swift), with [rerun instructions](reproducers/README.md), outside the compiled test target because runtime fixes are outside this approval. No disabled test or skip conceals its RED result. After approval of its fix, move it into the active suite and require GREEN.

Only tests and review documents changed. Package tests compile the added test file; no new app IPA or simulator/UI evidence is claimed because application source is unchanged. Hardware decoding, sustained playback and screensaver behaviour remain physical acceptance checks.

## Next bounded proposal

Fix per-video HLS cache invalidation before attempting a broader source-identity refactor. Own `HLSManifestCache.swift`, the necessary minimal cache support, and the existing recovery callers; preserve source ordering, codec/height policy, TTL/capacity, and unrelated videos' cache entries. Add the policy-key reproducer to the active suite with the fix. This changes recovery cache behaviour, so it requires separate approval.

Acceptance: all bare and policy entries for the affected video disappear; another video's entries remain; the same failing reproducer passes; current transition/end/seek tests remain passing; no new lint exceptions. Record the actual full gate outcome. Keep the candidate on its own branch/build and leave A's IPA intact until physical A/B acceptance.
