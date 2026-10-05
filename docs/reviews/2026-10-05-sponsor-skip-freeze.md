# Manual SponsorBlock skip investigation, 5 October 2026 NZ time

## Physical report and retained evidence

The user clicked the remote's Centre/Select button on Skip Preview / Hook and
reported a frozen app, including no response to Back/Menu. Installed app source
was `4cb22a6860e5b667f203d91adced8232ef14c49f`; later commits only added documentation.

Measured Pi capture, report `5BD5A204`, video `D2Ej0fXFReQ`:

- At 08:51:29 UTC playback was 4K, rate 1.5, position 5.563 s, buffer 32.677 s.
- At 08:51:34 UTC playback was paused, rate 0, item ready, position 11.116 s,
  buffer 52.244 s, with zero recorded errors, stalls or dropped frames.
- Later snapshot heartbeats continued with the stopped playback position.
- The preserved later sample contained 98 native segment events with 98
  received HTTP 200 transactions and no native request error.

Local safe evidence: `tmp/hook-freeze-first-events.json` and
`tmp/hook-freeze-preserved-events.json`. Raw signed resource URLs and credentials
were not retained in these sanitized event payloads. The timestamps identify
observed state, not the precise unlogged remote action time.

## Hypotheses and checks

1. A skip-triggered application-thread lockup: continued MainActor-generated
   heartbeats weaken this explanation for the captured interval. They do not
   prove that remote input or the SwiftUI focus tree remained responsive.
2. A seek waiting for unavailable media: the captured state was paused rather
   than waiting, with buffered media and no recorded media error. The successful
   native requests weaken an empty-buffer explanation, without ruling out an
   unrecorded or intermittent AVFoundation failure.
3. New native diagnostic subscriptions blocking the seek: independent code
   review found no pause/rate/seek/focus mutation in the diagnostic patch and no
   seek-specific reattachment path. This is inspection, not physical exclusion.
   A later matched build with only capture_id absent would distinguish this
   hypothesis while retaining baseline snapshots.

The direct manual route is SponsorBlockSkipManager.skipToastSegment → delegate
seek(to:) → AVPlayer.seek. A toast disappearance changes both player focusability
and a conditional remote-movement modifier. A delayed toast-focus task also
exists. Whether any of those transitions caused the physical failure remains
UNVERIFIED.

## Reproduction scope

Added a hermetic tvOS UI test using the existing description-toast fixture.
It dismisses the description, selects the enabled focused skip button, then
checks Up, Back and Up again. This exercises actual remote/focus routing but
uses the existing empty-media UI fixture: it cannot reproduce VP9 decoding,
YouTube delivery, or a seek across a real preview segment.

The first simulator run overlapped a review-owned native UI suite and was
terminated. Its result is unusable. The repeat is serialized with a separate
result bundle. A focus-property assertion timed out before Select, but removing
that implementation-specific assertion allowed the full Select/Up/Back/Up
sequence to pass on unchanged production code. The false focus indication does
not establish a functional input failure. The physical freeze was not reproduced.
Result: `tmp/hook-skip-input-functional-red.xcresult`, 1 passed, zero failures or
skips. The result folder name reflects the intended baseline test, not its result.
The final test placement in a same-file extension was rerun successfully:
`tmp/hook-skip-input-final.xcresult`, 1 passed, zero failures or skips. Full
`just ci` still failed lint at 150 violations; the extra type-length finding from
the initial test placement was removed without changing the lint baseline.

Existing SponsorBlockSkipManager tests passed 7 tests; they do not cover this
physical remote-input failure. No playback or UI fix has been applied or installed
during this investigation. A targeted physical capture of remote input, focus
and seek boundaries is still needed to establish which action actually ran.

The user confirmed TV/Home still works while SmartTube's Back does not. This
supports an app input/state problem over complete remote or system failure.
The physical Apple TV was not listed by `xcrun xcdevice list`, and a syslog CLI
was unavailable, so direct device-log capture was not established.

A later direct Mac-to-collector HTTP read timed out. The Pi container was
confirmed running over SSH; a Pi-local authenticated read succeeded and still
showed the same video paused at 11.116 s with no media error. The network-read
timeout does not erase the captured app evidence or establish a collector outage.
Local safe readback: `tmp/native-device-capture-events-ssh.json`.

Next physical check: force-close SmartTube, reopen the same video at 1.5× and
repeat the Centre/Select preview skip once. Do not claim reproduction or recovery
until the user confirms the outcome and the matching capture is assessed.
