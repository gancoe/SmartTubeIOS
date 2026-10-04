# HLS delivery diagnostics, 4 October 2026

## Status

This is a diagnostics candidate based directly on prepared baseline
`bba26b388571ead4932551c076a6d9c9e6f2788d`. It does not change playback policy,
quality caps, buffering targets, stream resolution, retries, caches or decoder
registration. Installation and physical acceptance of this candidate are pending.

## Observed problem

Cited: the user's 4 October 2026 reports describe three temporary quality drops
in 17 minutes during uninterrupted viewing, with recovery to 4K and no perceived
stall. A subsequent photo, report `74446D15`, shows actual resolution 854 x 480,
playback at 1.50x, a ready item, 174.7 media seconds buffered, empty=no,
keepUp=yes, Native4K/HLS, and a retained CoreMediaErrorDomain/-16830 log entry.
The user subsequently reported the buffer reaching 50 seconds and resolution
returning to 4K. No software change occurred between these observations.

The photo's absent download sample does not establish that media downloading
stopped: the existing binding displays a dash for an absent or nonpositive
observedBitrate. The 24.6 Mbps nominal value is selected-format metadata, not
the advertised bitrate of the current access-log period.

The cause of the quality drops is UNVERIFIED. Ranked hypotheses and checks:

1. Late media delivery: correlate a new error date/count and timeout comment
   with the resolution change and buffer remaining at the current speed.
2. Quality/buffer constraints at accelerated playback: observe the installed
   bitrate hint and actual delivered stream metadata, then test one policy
   variable at a time on a separate branch if supported by the trace.
3. Stream-source recovery: correlate stream type and playback-state changes
   with the quality drop. Native4K/HLS in the low-resolution photo argues
   against a persistent H.264-only fallback in that snapshot, but the label
   alone cannot establish item identity or absence of an earlier transition.

Apple's 2018 WWDC presentation, Measuring and Optimizing HLS Performance,
provides a -16830 example with the comment "Media file not received in 15s".
That example does not establish the comment, timeout duration, event time or
cause for this device's entry. The new candidate exposes these missing details.

## Change

- Preserve the error's native date, event count and known media-request timeout
  comment; display UTC time and age so retained entries remain distinguishable
  from newly reported errors.
- Keep only recognized timeout sentences in comments. Other comments display
  "Details redacted", avoiding URLs, request credentials and headers.
- Separate selected-format bitrate from the latest access period's server-
  advertised bitrate. These apply across AVPlayer stream types, not just HLS.
- Show accumulated transferred bytes paired with access-event count. This is
  the running total within the latest access-log period and may reset when a
  new period begins; it is not the last segment's size or continuous throughput.
- Read the item's installed preferredPeakBitRate without changing it.
- Display contiguous buffer duration divided by the actual positive player
  rate. Paused or unavailable/invalid rates report unknown viewing duration.
- Log quality, rate, route, playback-state and error changes locally through
  os.Logger, category PlaybackDeliveryDiagnostics, prefix [hls-delivery].
  Error date/comment and viewing buffer are included with the session report ID.
  This new logger does not forward to Firebase. No network collector is added.
- Correct the existing resolution breadcrumb's source label to presentationSize,
  matching its actual binding.

Collection uses the existing Stats refresh loop. Keep the Stats overlay visible
for the diagnostic run. There is no new always-on observer or background task.
An error with an unknown native date remains explicitly time/age unknown.

## Verification

Measured in this work session:

- Four new behavior tests first failed because the requested diagnostic interface
  did not yet exist, then passed after implementation. These are diagnostic
  feature tests, not a reproduction or regression test of the network timeout.
- 93 tests across 6 focused suites passed, including diagnostics, item failures,
  native recovery, native manifest/policy and quality checks.
  Log: `tmp/hls-delivery-diagnostics-focused-final.log`.
- tvOS simulator build succeeded.
  Log: `tmp/hls-delivery-diagnostics-tvos-build-final.log`.
- Changed-file strict lint: 0 violations across 3 files.
  Log: `tmp/hls-delivery-diagnostics-scoped-lint-final.log`.
- Full `just ci` stops at 148 existing lint violations outside changed files.
  Secret, documentation-link and format checks completed before that failure;
  the full unit stage was not reached.
  Log: `tmp/hls-delivery-diagnostics-ci-final.log`.
- Independent cross-model review found two misleading labels; both were
  corrected. Its final live-tree review found no remaining P1/P2 issues.

Limitations: Apple's access/error event classes have unavailable initializers,
so tests cannot fabricate native log events. Real view-model tests cover player
buffer/rate/configuration reads and no mutation; helper tests cover event age,
safe comments and unknown/invalid bitrate values. Physical acceptance must
confirm that native event extraction populates the expected fields. Simulator
compilation or helper tests do not establish reliable 4K at 1.5-2x.

## Next physical run and fix gate

Install only after the user is ready to end the current playback session.
Keep the prepared A artifact and separate cache-fix B artifact unchanged.
Play the same known-4K video at the user's normal 1.5x and 2x speeds with Stats
visible. Capture the new error time/count/comment, advertised bitrate, transferred
total/access count, viewing buffer and route at a quality drop and its recovery.

If a new -16830 event aligns with each drop, investigate that media request's
delivery and buffer/quality policy. If the error date stays old through later
drops, it is not evidence of a new timeout for those later drops. Change one
supported variable per candidate, with a regression test at the actual policy
seam where feasible, and compare device behavior against baseline at 1.5-2x.
No successful recovery is to be reported as a fix without a tested software
change and repeatable physical improvement.
