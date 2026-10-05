# Native 4K buffer experiment, 5 October 2026

## Problem and evidence

The uncapped source `8bc308106eb233f24cc23d989feaebb6c73f1337`, report `01AEF2F7`, reached 4K after four seconds but subsequently downgraded twice and logged CoreMedia -16830. The first transition followed HTTP/3 video requests taking 14.3796 and 11.7016 seconds for 5.24/5.32 seconds of media. Both returned HTTP 200. At 1.5×, those segments supply approximately 3.5 seconds of viewing time. Removing the app bandwidth preference did not eliminate the problem.

Measured from the preserved capture: typical 4K buffer was about 50 media seconds. Initial Native4K playback requests 0.5 seconds, then returns to Apple's automatic buffering after five seconds. Ordinary HLS quality reload requests two seconds before the same reset. Zero means system-selected buffering, not no buffering.

Alternative explanation: a permanent 1080p cap cannot account for captured 4K playback; the uncapped preference remained zero. A proxy timeout is not the direct media-request explanation because native media segment URLs remain HTTPS and AVPlayer owns their transactions. CDN/network delays versus native-client behavior remain UNVERIFIED.

## Established implementation audit

[Apple HTTP/3 documentation](https://developer.apple.com/documentation/foundation/urlrequest/assumeshttp3capable) says the request flag enables QUIC racing without discovery. False is not an HTTP/3 prohibition. The local tvOS SDK agrees. No supported per-AVURLAsset HTTP/2-only control was found in the examined public interfaces. Changing the proxy loader's URLSession would not alter the direct native segment requests. A private CFNetwork setting or a media relay would introduce an unverified mechanism or replace the delivery route; neither is part of this experiment.

[Android SmartTube's buffer implementation](https://github.com/yuliskov/SmartTube/blob/master/common/src/main/java/com/liskovsoft/smartyoutubetv2/common/exoplayer/other/ExoPlayerInitializer.java) exposes 50/100-second options with a device-dependent byte budget. Its [network engine options](https://github.com/yuliskov/SmartTube/blob/master/common/src/main/java/com/liskovsoft/smartyoutubetv2/common/prefs/PlayerTweaksData.java) offer different networking libraries. These provide precedent, not a transferable tvOS fix. The Android infinite-loading [issue 6030](https://github.com/yuliskov/SmartTube/issues/6030) concerns startup through a VPN and does not establish this session's cause.

[Apple's forward-buffer preference](https://developer.apple.com/documentation/avfoundation/avplayeritem/preferredforwardbufferduration) is supported on tvOS. A higher value increases resource demand, and the SDK explicitly allows buffering less to manage consumption.

The user supplied [Ian Duncan’s HTTP/3 benchmark article](https://www.iankduncan.com/engineering/2026-02-10-http3-not-always-faster/). Its local 50–100× result is implementation-specific. The cited [WWW 2024 research](https://arxiv.org/abs/2310.09423) measured HTTP/3 throughput deficits in some high-speed environments, including video delivery. This strengthens the reason to compare transports but does not identify the cause on this Apple TV. Fast and slow HTTP/3 transactions coexist in this capture; protocol presence alone cannot explain the intermittent delays.

The user also supplied [ShiftCTRL’s App Store/UniFi diagnostic article](https://shiftctrl.net/articles/unifi-apple-app-store-slow-downloads). Transferable principles are measuring the affected endpoint rather than speed-test throughput, distinguishing CDN selection from raw line speed, and isolating changes. Its Apple-CDN and UniFi remedies do not establish applicability to Google video delivery through Deco X55. Endpoint/connection correlation is a follow-up diagnostic lead; it is not bundled into the buffer intervention. A single fast unrelated transfer does not exclude every selective routing or policy failure.

## Isolated intervention

Astra approved preparing a Native4K-only 100-media-second steady-buffer preference. Preserve fast startup; apply after the existing five-second interval on initial playback and ordinary HLS quality reload. Capture the target before waiting, use weak item ownership, and do not apply after cancellation. Other routes and forced H.264 recovery retain automatic steady buffering. Retain the uncapped preference, resolution/codec/audio filtering, request path and recovery behavior. No router or topology changes.

100 media seconds represents 50 seconds at 2×. At the recorded advertised 33.12 Mbps, the nominal encoded payload is about 414 MB; this is a calculation, not measured process memory. The system may decline the target. No indefinite buffer or hard quality lock is requested.

## Physical acceptance and rollback

Retain the installed uncapped IPA for rollback. A separate candidate capture must identify the new source and must not renew the previous session. Test the same video at 1.5×, initially without seeking, bounded to 20 minutes. First establish whether actual 4K headroom rises materially above the baseline. If not, the intervention was not achieved and the result is inconclusive. Then compare slow request completion, buffer depletion, downgrades, errors, stalls, audio and navigation. Lack of comparable slow requests proves feasibility only. Assess 2× separately after a useful 1.5× result.

This is a resilience experiment. It does not establish or repair the origin of delivery delays. Simulator/unit tests establish configuration and lifecycle behavior only; they cannot validate physical VP9 decoding or sustained 4K.

## Validation status

Measured on resumption: 39 related tests in four suites passed (`tmp/native-4k-buffer-related-tests.log`), including real AVPlayerItem buffer application, forced-H264 isolation, parked non-HLS rearm, target capture, cancellation/replacement, the real stop path and existing item-failure recovery. The tvOS simulator build passed (`tmp/native-4k-buffer-tvos-build.log`). Required `just ci` reached lint and failed with 150 serious violations in 419 files (`tmp/native-4k-buffer-ci.log`); the lint baseline was not changed. Independent review found no actionable defects in the updated lifecycle. Private Release archive and device acceptance remain pending.

The initially reviewed candidate had lifecycle defects: stop cancelled a ramp that hot reopening did not restart, and an obsolete initial attempt could replace a newer ramp before its cancellation guard. The resumed implementation rearms parked items using the last accepted HLS/non-HLS eligibility, schedules initial ramps only after final cancellation/video guards, and excludes forced H264 recovery from the native target. Manager tests cover these policies. The complete hot-load and attemptURL delayed-mutation paths are checked by source inspection rather than deterministic end-to-end timing tests; the existing five-second default wait has no injected seam at those full call sites. No red-green end-to-end claim is made.

Yattee was installed separately for an alternate-player trial. Its Pi backend passed authentication, format extraction and bounded 4K byte-range checks. Sustained TV playback remains unverified; neither that trial nor these code checks establish that delivery delays or quality drops are fixed. Installation evidence is retained privately under `tmp/yattee-trial/`.
