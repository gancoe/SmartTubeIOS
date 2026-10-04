# HLS recovery cache invalidation

Date: 4 October 2026. Scope: approved cache correction on `fix/hls-recovery-cache-invalidation`, independently based on prepared baseline `bba26b388571ead4932551c076a6d9c9e6f2788d`. The audit remains on `test/native-recovery-regressions`; only its accepted transition-test foundation is carried into this branch.

## Problem and evidence

HLS policy entries use `videoID|height|codecs` (`HLSPlaybackPolicy.swift:72`). Existing quality/403 recovery callers invalidate the raw video ID (`PlaybackViewModel.swift:657` and `PlaybackViewModel+Fallback.swift:1774,1791,1856,1872`). The original cache invalidation removed only that exact key. Fresh native and H.264 policy entries therefore survived recovery.

Measured RED: the original reproducer ran against the unchanged baseline and failed with two expectations, one for each policy entry. Source: `tmp/hls-cache-fix-red.log`. TTL expiry is an alternative explanation ruled out by freshly stored entries and immediate invalidation; bare-entry removal succeeded in the same test. This establishes a cache-contract mismatch, not a diagnosis of the physical freeze.

## Change

The existing `HLSManifestCache.invalidate(for:)` now removes the exact ID and policy entries beginning with that ID followed by the `|` delimiter. Internal `TTLCache` support snapshots matching keys before removal. Existing recovery callers remain unchanged. Other video IDs, including IDs sharing the same prefix, remain cached. The public method, TTL, capacity, source ordering, codec/quality policy and player lifecycle are preserved.

Only `HLSManifestCache.swift` and `TTLCache.swift` change runtime behaviour. No fallback branches, player engine, authentication, remote UI or preloading changes are included.

## Validation

Measured parent run: 73 tests in 11 suites passed without skips. Source: `tmp/hls-cache-fix-focused-final.log`. It covers the formerly failing reproducer, adjacent-video/policy retention, repeated missing-video invalidation with unrelated data, generic TTL/capacity behaviour, native source/policy/manifest rules, recovery, seeking, item failure, end observation and prefetch. The transition foundation from the audit still passes.

Scoped SwiftLint reports zero violations across both changed runtime files and both added test files. Source: `tmp/hls-cache-fix-scoped-lint.log`. Independent Terra review found no P1/P2 finding in the live diff; it verified the delimiter match, key snapshot, unchanged TTL/capacity semantics and real cache/policy test seam.

`just ci` passes secrets, documentation links and formatting, then fails at 148 existing lint violations. Source: `tmp/hls-cache-fix-ci.log`. It does not reach its unit-test step. No lint-baseline regeneration, disabled test or skip is used to conceal this failing repository gate. Focused unit evidence is separate.

## Confidence and limits

The before/after replay establishes that the missing invalidation is corrected and unrelated entries remain. A filtered manifest fetch can previously reuse stale policy metadata (`PlaybackViewModel+Fallback.swift:1023`). The filtered route supplies its master URL to AVPlayer (`:1069`); this fix does not establish an expired variant URL was directly decoded or that invalidation caused the reported freezes.

Actual sustained playback, decoded 1440p/4K output and physical recovery remain UNVERIFIED. Settle those by testing the prepared baseline A, then this separately identifiable candidate B with the same video/settings and recorded sequence. Repeat unexpected differences because YouTube responses can vary. No TV wake, installation or playback contact is part of this work.

A separate unsigned candidate archive may be prepared after commit. Its build log, checksum and source provenance live with the release artifact and in `tmp/hls-cache-fix-artifact-verification.json`; only a successful build confirms preparation. The original A IPA remains intact and must be verified before any physical comparison. Do not merge/promote B before physical acceptance.
