# In-video MPV trial for Apple TV

This experiment adds **Player → AVPlayer → MPV (experimental)** to the video's More menu. AVPlayer remains the default. MPV opens with its own controls and offers **Return to AVPlayer**. Switching preserves the video, position, playback speed, and play/pause intent; the outgoing AVPlayer item is detached before MPV starts.

## Scope

- MPVKit is pinned to 1.0.0, revision `288527dffbc6d3e63cce147fc7b520c64a791603` in both package resolution files.
- The trial uses the active HLS source's original HTTPS master and the exact headers captured at AVPlayer asset creation. Proxy URLs are normalized before matching. Compositions, stale sources, and non-HLS routes cannot enter the trial.
- MPV uses FFmpeg demuxing and the MPVKit Metal/MoltenVK surface, requests VideoToolbox hardware decoding, and selects the highest HLS rendition. Actual codec, hardware decoder, resolution, FPS, cache throughput, and buffer are visible in its Stats overlay.
- The requested forward cache is 100 media seconds, subject to a 256 MiB forward byte limit. It is finite and can reach the byte limit before reaching the duration target.
- Basic play/pause, seeking, 1–2× speed, and the shared SponsorBlock decision policy are supported. Play pressed during loading updates the eventual playback intent.
- Background audio follows the existing Background Playback preference. Video output is disabled while backgrounded. The screen idle timer is disabled during playback.
- MPV's trial controls are separate from AVPlayer's quality, captions, recommendation, channel, and autoplay UI. Returning to AVPlayer restores access to those controls. MPV is an experiment, not a replacement for all existing player features.

## Remote diagnostics

MPV snapshots use the existing private Pi collector with a distinct `MPV/FFmpeg/HLS` route and `MPV` error domain. They include resolution, position, speed, buffer, cache throughput, decoder frame-drop count, cache-wait transitions, and sanitized numeric errors. They do not contain AVPlayer request/variant timings. MPV throughput is its one-second cache-read sample, not an AVPlayer access-log average. Codec and FPS remain on-screen only.

The MPV queue has its own `MPVDiagnostics/pending.json` file. On tvOS, capture uses the same `UserDefaults.standard` state store as AVPlayer. Capture reuses the configured UUID and persisted deadline; switching engines does not renew the 30-minute limit. Initialization failures can emit one final snapshot.

Measured: four payload fixtures compiled from the production Swift event types and mapper passed the collector validator; the Pi accepted a synthetic `testonly` error event with HTTP 201 (`tmp/mpv-collector-contract-verification.json`). This verifies payload/transport compatibility, not installed-app delivery.

## Comparison limits

The source URL and authentication headers are shared. The playlist presented to the engines is not identical: AVPlayer's route can apply its local codec/height filter, while MPV reads the original master directly and requests its highest rendition. This tests the complete MPV playback path; it cannot isolate engine effects from rendition-selection differences. Stats must confirm the actual selected codec and decoder.

Neither a successful build nor healthy startup establishes sustained physical 4K playback. The TV test should include the same 4K/30 and 4K/60 videos at 1.5× and 2×, a seek, a SponsorBlock skip, a paused handoff, and a return to AVPlayer. Retain the installed 100-second-buffer IPA as rollback.

## Validation record

- Measured: the integrated tvOS simulator build completed successfully (`tmp/mpv-final-simulator-build.log`). This confirms integration, not physical decoding.
- Measured: 40 focused tests in five suites passed (`tmp/mpv-final-focused-tests.log`), covering the source/handoff gate and the existing native buffer/failure policies.
- Measured: `just ci` stopped at lint with 149 serious violations in 429 files (`tmp/mpv-ci.log`). No violations were reported in the new trial files; the full gate remains failing. The lint baseline was not changed.
- An independent reviewer found and verified repairs for proxy-source matching, background preference handling, and early remote Play intent.

## First physical startup failure and bounded repair

The first installed trial showed `Unable to start video playback` before media loading. The saved capture (`tmp/native-mpv-first-startup-failure-events.json`) contains AVPlayer events but no MPV route, so actual MPV delivery is still unverified. The installed generic message covered both handle creation and rejected startup calls; it did not identify the failing stage.

A direct probe of MPVKit 1.0.0's macOS slice reproduced `mpv_create=NULL` with `LC_NUMERIC=en_NZ.UTF-8`, then successful creation and initialization after `setlocale(LC_NUMERIC, "C")`. All configured options were accepted by that slice (`tmp/mpv-locale-probe-parent-verification.log`). The bundled tvOS header requires the C numeric locale for libmpv's lifetime. The repair enforces that documented precondition when entering the MPV trial; it changes only the numeric locale, not Foundation's selected display language or region.

UNVERIFIED: the physical failure was caused by its locale. The device locale was not captured; tvOS-specific option/initialization failure and handle-creation memory failure remain alternatives. The next build therefore also shows the exact startup stage and records real numeric return codes. Creation failures without a libmpv return code emit a failed-item event without inventing a code. The new diagnostic test first failed with `unknown` status, then passed after that mapping was corrected (`tmp/mpv-startup-failure-test-red.log`, `tmp/mpv-startup-repair-tests-final.log`). Physical playback remains the acceptance gate.

Repair validation: 41 focused tests passed, the final tvOS simulator build succeeded, and independent review found no remaining startup telemetry blockers. `just ci` still stopped at the inherited 149 serious lint violations in 429 files (`tmp/mpv-startup-repair-tests-final.log`, `tmp/mpv-startup-repair-build-final.log`, `tmp/mpv-startup-repair-ci-final.log`).

## Physical startup identifies an unavailable tvOS option

The repaired build's physical error was `MPV startup failed at ytdl (-5)` (user-supplied photo, 6 October 2026). The bundled tvOS `client.h:312` defines `-5` as `MPV_ERROR_OPTION_NOT_FOUND`. This establishes a rejected startup option before `mpv_initialize` or `loadfile`; a network or decoder failure cannot produce this stage. The numeric-locale hypothesis did not explain this failure.

The pinned MPVKit build script (`Sources/BuildScripts/XCFrameworkBuild/main.swift:414-432`) enables Lua on macOS and disables it on other platforms. This explains why the macOS bootstrap probe accepted `ytdl` while the Apple TV rejected it. The repair removes the unnecessary `ytdl=no` option: the trial receives SmartTube's already-resolved HTTPS HLS source and does not need YouTube extraction scripting. No stream source, buffering or AVPlayer policy changes are included. Physical playback after removal remains unverified.

The review also found that the MPV capture was file-backed while AVPlayer explicitly used `UserDefaults.standard` on tvOS. The MPV monitor now uses that same defaults store, preserving AVPlayer's capture start and deadline rather than creating an independent window. Existing defaults-persistence tests cover reopening and expired captures. Whether this mismatch caused the missing MPV events remains unverified until device delivery is measured.

## Physical loading and remote controls

Measured on 6 October: after removing `ytdl`, the device delivered 13 MPV snapshots over 29 seconds for video `BkWKScGrF38`, report `7EA3980E`. They showed an unknown item, zero buffer, no resolution, no numeric error, and unchanged inherited position. The old `playing` label represented requested play intent, not loaded media (`tmp/native-mpv-no-start-events.json`). Subsequent AVPlayer events showed 4K playback; this does not prove why MPV did not load during that interval.

The controls initially assigned focus to Play/Pause while its containing row was disabled until readiness. The local repair focuses Return during loading, switches focus to Play/Pause when ready, and displays a loading indicator. Diagnostics now report waiting for an unloaded session and cannot report a failed item as playing. These controls remain unverified on the physical remote.

The loading-state and failed-item tests first failed before repair, then 42 focused tests passed (`tmp/mpv-loading-state-red.log`, `tmp/mpv-failure-playback-state-red.log`, `tmp/mpv-loading-state-tests-final.log`). The explicit tvOS simulator build succeeded (`tmp/mpv-loading-state-build-explicit-final.log`). Independent review found no remaining blockers in this diff. `just ci` still stopped at 149 inherited serious lint violations in 429 files (`tmp/mpv-loading-state-ci-final.log`); the baseline was not changed.

A local-file probe against the bundled tvOS simulator library received `FILE_LOADED` and `PLAYBACK_RESTART`. A fresh HLS source for the affected video, with rendering disabled, reached `FILE_LOADED` at 23.12 seconds and reported 3840×2160 (`tmp/mpv-load-probe-result.log`, `tmp/mpv-youtube-hls-probe-output.log`). This confirms those probe paths can load. It does not rule out slower physical loading, differences in the original signed source, or a problem in the production Metal/session path. Actual MPV video rendering and playback remain unverified.

## Upstream references

- [MPVKit](https://github.com/mpvkit/MPVKit), including its tvOS Metal example and drawable-size workaround.
- [MPV manual](https://mpv.io/manual/stable/), for HLS rendition selection, bounded caching, async commands, and cache-speed units.
- [Yattee MPV client](https://github.com/yattee/yattee/blob/main/Yattee/Services/Player/MPV/MPVClient.swift), used as an architectural reference. SmartTube's YouTube account and browsing path are retained.

Configured IPAs, signed stream URLs, capture tokens, server credentials, and local capture evidence remain private and are not published to GitHub.
