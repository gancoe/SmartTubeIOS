# Apple TV playback freeze investigation, 4 October 2026

Tracking: [personal issue #1](https://github.com/gancoe/SmartTubeIOS/issues/1).

## Reported physical behaviour

The user reports stopped picture, audio and playback time with a responsive
interface. The ten-second forward control did not resume playback; leaving
and reopening the video is the current workaround. An earlier video played
at 1080p without this symptom.

The user-supplied photo displays 1920x1080 on the `VisionOS/HLS` stream source,
a nominal bitrate of 5.0 Mbps and observed download bitrate of 31.2 Mbps,
with zero reported stalls or dropped frames. Nominal bitrate and frame rate
are format metadata; observed bitrate and counters come from the last
AVPlayer access-log event. These are not a live buffer or error measurement.
`mp4` is a metadata/container label, not proof of the active decoded codec.
`pi:MISS wkHLS:MISS` describes resolver caches at load time, not media buffering.

Output resolution alone therefore does not distinguish the reported working
and failing sessions. The cause remains UNVERIFIED. Stream starvation and
player/item failure remain alternatives; the available photo cannot rule out
either. Physical syslog capture was attempted but could not discover the
network device, so no error or crash signature was obtained.

## Controlled observation finding

The production `AVPlayerItem.statusStream` terminates at `readyToPlay` or
`failed`. A local controlled AVPlayerItem issued real KVO transitions from
unknown to ready to failed. The production stream yielded unknown, ready,
then nil, while the item itself reported failed. The parent recompiled and
repeated that result using Swift 6 and warnings as errors. Local artifact:
`tmp/status_stream_gap_harness.swift`.

This reproduces lost post-ready failure observation. It does not reproduce
the physical freeze or prove that the same defect caused it. Some inline
stream attempts depend on the readiness stream finishing; changing its
lifetime globally would alter that contract.

## Diagnostic build scope

Expose actual player and item status, waiting reason, playback rate,
contiguous buffered seconds ahead, buffer flags and sanitized error codes in
Stats for Nerds. Refresh visible diagnostics using wall-clock time so the
readings can change while the playback clock is stopped.

Error diagnostics include only domains and codes. They do not expose signed
stream URLs, account credentials or error descriptions. There is no new
telemetry upload. Quality selection and playback recovery are unchanged;
this is an evidence-gathering build, not a freeze fix.

## Validation

- Five diagnostic regressions passed through the actual view-model snapshot
  method with controlled AVPlayer/AVPlayerItem getters. They cover waiting
  state, current-item buffer boundaries, absent item, sanitized errors, and a
  transition to failed after playback stops. Source:
  `tmp/playback-diagnostics-parent-green.log`. Initial RED compilation
  rejected the missing diagnostic fields before implementation:
  `tmp/playback-diagnostics-red.log`.
- Final focused native unit run: 109 tests across nine suites passed. Source:
  `tmp/playback-diagnostics-unit-final.log`.
- Settings simulator checks: eight passed, zero failed and zero skipped.
  Source: `tmp/native-tvos-tests.3eKk5y/settings.json`. That run preceded a
  behaviour-preserving snapshot-helper extraction and label corrections;
  the final unit run covers the extraction. The unsigned Release archive
  will verify compilation of the final tvOS presentation changes.
- Independent review found no lifecycle, cancellation, buffer-contiguity,
  privacy or production-seam defect. Its two presentation findings were
  addressed by renaming `Codec` to `Codec metadata` and `Connection Speed`
  to `Download sample`.
- Secrets, documentation links and strict formatting passed in `just ci`.
  The full gate still stops at 137 lint violations, matching the prior
  baseline. The two new length violations introduced during implementation
  were corrected. Source: `tmp/playback-diagnostics-ci-commit.log`.

Simulator and controlled-player tests cannot verify actual YouTube delivery
or media-service state on the physical Apple TV. No freeze fix is established.

## Real AVPlayer delivery-fault simulation

A local generated H.264/AAC 1080p HLS fixture was served through a loopback
HTTP server. The harness uses the real macOS AVPlayer and measures its media
clock; it is not a simulated button or a copied recovery calculation. Later
segments were deliberately blocked with HTTP 503 responses. Artifacts and
rerun instructions are in ignored `tmp/hls-stall-simulation/`.

| Phase | Measured media time | Final player state |
|---|---|---|
| Normal delivery | 0.00 to 6.91 seconds | Playing, rate 1, item ready |
| Blocked delivery | Drains to 17.87 seconds, then stops | Waiting, rate 1, item ready, buffer empty |
| Forward seek while blocked | Jumps to 27.87 seconds and stays there | Waiting, rate 1, buffer empty |
| Unblock and reload | 27.87 to 35.16 seconds | Playing, rate 1, item ready |

Source: `tmp/hls-stall-simulation/run4.jsonl`, independently parsed by the
parent. The local server recorded nine HTTP 503 responses in
`tmp/hls-stall-simulation/server.jsonl`; the player's last error-log event
reported `CoreMediaErrorDomain#-16849`. A forward seek did not recover play
while the delivery fault remained active.

Unblocking and reloading happened together, so this run cannot attribute
recovery to either action alone. It reproduces the reported stopped-clock
and ineffective-seek pattern under a known delivery failure, not the actual
Apple TV cause. It does not verify decoded pixels or the app's automatic
recovery. The existing app recovery guards require rate zero; this measured
waiting state retains rate one. The diagnostic build can establish whether
the physical session enters that same state before a recovery change is made.

## Physical media-services reset capture

A second user-supplied photo on 4 October 2026, report `D2C28701`, displays:

- Playback paused, rate 0.00, no waiting reason.
- Item failed; item and player errors both `AVFoundationErrorDomain#-11819`.
- Loaded ranges 49.8 seconds ahead, with buffer-empty yes and likely-to-keep-up no.
- VisionOS/HLS, presentation size 1920x1080; nominal bitrate 5.0 Mbps and last
  download sample 89.7 Mbps.

These are cited observations from the photo, not a continuous device trace.
The tvOS SDK `AVError.h` binds -11819 to `AVErrorMediaServicesWereReset`.
The alternative of an ordinary waiting-for-network state does not explain
an item marked failed with this error. The preceding delivery, decoder and
media-service events are unknown: the reset trigger remains UNVERIFIED.
Loaded time ranges describe retained item metadata after failure, not proof
that those seconds can still be decoded. The download sample is historical.

The production status-stream replay was repeated and still returned unknown,
ready, then nil for an item whose final state was failed. That confirms the
post-ready observation gap independently of the physical reset trigger.

## Media-services reset recovery patch

A separate current-item watcher observes this specific failure throughout
playback and exposes the existing error banner. The finite readiness stream
is unchanged. Play or Try Again initiates a fresh AVPlayer, rebinds the quality,
audio and SponsorBlock managers and player observers, and retains the latest
requested position for the existing ready-item restore path. It does not
change stream selection, codecs or the 1080p native stream cap.

Recovery requires user action, following [Apple QA1749](https://developer.apple.com/library/archive/qa/qa1749/_index.html).
iOS is excluded from this patch because its persistent player host needs a
separate player-layer rebinding change; macOS provides the offline test seam.

The initial production-seam test failed because a ready item followed by a
media-services reset exposed no retry error (`tmp/item-failure-red.log`).
A second RED run without the rebuild call failed the new-player and manager
rebinding assertions (`tmp/item-failure-rebuild-red.log`). Six focused checks
then passed (`tmp/item-failure-suite.log`), covering failure detection, Play
rebuild, position preservation, replaced-item/video guards, queued stop
cancellation, and error-domain discrimination. These inject real KVO events
into controlled AVPlayer and AVPlayerItem subclasses; they do not reproduce
a physical media-server crash or confirm restored physical playback.

Final validation of the recovery patch:

- Seven item-failure checks passed. The parked-item regression was first
  observed failing in `tmp/item-failure-parked-red.log`, then passed after
  re-establishing observation on the same-video fast path.
- Final focused run: 116 tests in ten suites passed, with no skips.
  Source: `tmp/media-reset-unit-final.log`.
- Settings UI: eight passed with zero failures or skips.
  Source: `tmp/native-tvos-tests.bQKtGr/settings.json`. This run preceded the
  parked-item observer fix and the extraction of the existing delayed stall
  seek into a helper. Final unit checks cover the updated source; the Release
  archive will check final tvOS compilation.
- Independent review reproduced the parked-reopen observation gap. That
  finding was fixed and re-reviewed; final helper extraction review was clear.
- `just ci` passed secrets, documentation links and strict formatting, then
  stopped at 137 lint violations, the same count as before the patch.
  Source: `tmp/media-reset-ci.log`. Full CI is not green.

The patch has not yet been verified on the physical Apple TV. These checks
establish reset detection and retry preparation through production code,
not prevention of the media-services reset itself.
