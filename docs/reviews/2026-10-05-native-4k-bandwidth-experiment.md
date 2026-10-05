# Native 4K bandwidth-limit comparison

## Decision

Prepare a separate experimental build from the installed native diagnostic
baseline. Astra approved this scope on 5 October 2026: remove only the artificial
preferred peak bandwidth limit for Native4K HLS. This is a hypothesis test, not
a confirmed playback fix. Track it in [issue #15](https://github.com/gancoe/SmartTubeIOS/issues/15).

Native4K initial playback and same-route quality changes use zero for
`preferredPeakBitRate`. Keep the existing maximum resolution, codec/audio
filtering, buffering, recovery and diagnostic bounds. H.264-only and forced
H.264 recovery retain their existing bitrate limits. The SponsorBlock input
investigation, Stats Back dismissal and cache branches remain separate.

## Measured physical evidence

Installed source `4cb22a6860e5b667f203d91adced8232ef14c49f`, report `3600993D`,
video `D2Ej0fXFReQ`, playback at 1.5× with 2160p selected. The same item stayed
at 1080p, reached 4K and then dropped quality without a recorded error.

At 09:15:34 UTC, a non-cached 5.32-second video segment completed in 10.3355
seconds. Its first response arrived in 0.0066 seconds; HTTP status was 200.
Buffer was approximately 5 seconds and subsequently fell to 3.3 seconds before
the quality dropped. The large low-quality buffer accumulated afterward.
At 09:21:02 the item was back at 4K, playing at 1.5× with no recorded error.
Private evidence is retained in `tmp/native-4k-baseline-capture.json` and
`tmp/resumed-1080p-evidence.json`; no credentials or signed media URLs belong
in published artifacts.

Apple defines [responseEndDate](https://developer.apple.com/documentation/foundation/urlsessiontasktransactionmetrics/responseenddate)
as the time after the task receives its final resource byte. The mapper computes
the transaction interval from request start to that date. A successful status
does not establish timely completion. CDN/network delivery versus client
backpressure remains UNVERIFIED.

The stream advertised 33.12 Mbps while the item preferred a 45 Mbps network
limit. Calculated consumption at 1.5× is approximately 49.67 Mbps before
additional overhead; at 2×, approximately 66.23 Mbps. Apple documents
[preferredPeakBitRate](https://developer.apple.com/documentation/avfoundation/avplayeritem/preferredpeakbitrate)
as a desired network-consumption limit. Its precise interaction with accelerated
playback here remains UNVERIFIED; the calculation alone is not root-cause proof.

## Existing online work

- [Upstream freeze issue #108](https://github.com/milika/SmartTubeIOS/issues/108)
  remains open. Similar symptoms do not establish a common cause.
- [Apple's HLS performance session](https://developer.apple.com/videos/play/wwdc2018/502/)
  documents -16830 with slow media-file delivery, not a universal app-code fix.
- [iOS/tvOS 26 developer report](https://developer.apple.com/forums/thread/801549)
  describes -15628 and preceding -12889 failures. No verified solution appeared
  in the retrieved discussion.
- A [UniFi-specific reported fix](https://community.ui.com/questions/Solved-Video-Streaming-drops-via-UXG-Lite-NSS-ECM-offload/74ea0763-1a17-4422-b219-74c741f3307f)
  concerns router offload and QUIC/TCP handling. Jonathan reports a TP-Link X55,
  so this router-specific intervention does not apply.
- [TP-Link's X55 YouTube report](https://community.tp-link.com/en/home/forum/topic/830342)
  describes poor streaming despite full speed tests. Support suggests DNS and
  double-NAT checks; the retrieved thread does not demonstrate a successful
  result from the reporter. These remain leads, not validated fixes.

Upstream [PR #129](https://github.com/milika/SmartTubeIOS/pull/129), commit
`2320131b5bb7a60af9505278d1fcedd62ad1170c`, was measured as an ancestor of
installed source `4cb22a6`. It fixes 360p startup through an H.264-only 1080p HLS
route; reapplying it would not address the current 4K downgrade. The iOS embedded
player remedy in [issue #97](https://github.com/milika/SmartTubeIOS/issues/97)
is not this native tvOS route. The post-ready media-services-reset recovery
proposed in #108 is already covered locally; this event had no recorded reset.
No verified upstream patch matching this exact transition was identified.

Jonathan reports Ethernet from the Apple TV to another X55 with Ethernet
backhaul. Keep network configuration unchanged during the app comparison.

## Comparison and rollback

Retain the installed baseline IPA, SHA-256:
`66f36c6ac2085d7e1c7fe8de5956ea0f4ac2528f346f211bdd2c594d557b9b6c`.

The experimental build gets a separate explicitly prepared capture UUID;
reopening must not extend its persisted 30-minute diagnostic bound. Compare
matched 15-minute windows of the affected video at 1.5×, initially without
seeking. Measure sustained 4K, downgrades after reaching 4K, preceding request
durations and buffer, stalls, audio and playback continuity. Different time
spent requesting 4K is a confound and must be recorded.

If improved, repeat in reverse order before treating it as a candidate fix.
Then assess 2× separately. A higher bandwidth requirement and possible exposure
to more slow 4K requests are material risks. Missing reproduction or mixed
results means inconclusive. Tests verify policy scope, not physical improvement.

## Local verification

- Seven Native4K policy tests passed, including actual manager configuration,
  H.264 limits and reset behavior: `tmp/native-4k-uncapped-policy-tests.log`.
- Twenty-two tests in three related suites passed:
  `tmp/native-4k-uncapped-related-tests.log`.
- `git diff --check` passed.
- `just ci` passed secrets/format checks but failed lint with 150 serious
  violations in 419 files. The lint baseline was not changed. This is not a
  green full-repository gate: `tmp/native-4k-uncapped-ci.log`.
- `just build-tvos` exited successfully:
  `tmp/native-4k-uncapped-tvos-build.log`.
- Independent code review found no blocker and confirmed initial load,
  quality changes and forced H.264 recovery retain the intended scope.
- Release build, installation and physical comparison are pending.
