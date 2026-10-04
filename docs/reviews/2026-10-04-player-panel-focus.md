# Apple TV player panel focus

Date: 2026-10-04
Scope: personal `gancoe/SmartTubeIOS` fork, `native-tvos` branch; issue [#3](https://github.com/gancoe/SmartTubeIOS/issues/3).

## Diagnosis

The installed recommendations panel intermittently had no highlighted card and did not respond to Up, Back or directional input. The player disabled its remote handlers as soon as the panel opened, then relied on a delayed card-focus request to restore input. Losing that handoff leaves no active panel responder.

The alternative that NavigationStack alone prevents dismissal was insufficient: three ordinary navigation-route tests passed. A controlled test that prevented native card focus then failed to dismiss with Up. Source: `tmp/recommendations-navigation-repro.xcresult` and `tmp/recommendations-focus-loss-red-summary.json`. The physical timing trigger remains UNVERIFIED; the new build must be tested on the Apple TV.

Review found another focus owner: a SponsorBlock toast scheduled focus on its Skip button even while recommendations were open. A simulator regression failed when Right did not select the next recommendation. Source: `tmp/recommendations-toast-red-summary.json`.

Description had a different missing handoff. Selecting its More-menu row removes the focused row, but the description's Close button had no focus binding or explicit initial focus. The player also yielded focus while Description was open. The new More → Description → Back regression exited the player before the fix, then passed after adding Close-button focus. A toast is not required to reproduce that failure. Sources: `tmp/description-back-red-summary.json` and `tmp/description-back-green-summary.json`.

With Close-button focus added, Back still dismissed Description when a toast appeared, ruling out the hypothesis that the toast necessarily breaks Back. However, Select activated the underlying Skip prompt instead of Description's Close button, leaving Description open. Source: `tmp/description-toast-back-summary.json` and `tmp/description-toast-select-red-summary.json`.

The user subsequently reported the same Back failure in Comments. Its shared overlay had the same missing Close-button focus binding. A More → Comments → Back regression also exited the player before the fix. Source: `tmp/comments-back-red-summary.json`. Its Close button now claims focus outside the loading/empty/content branches; comment fetching remains unchanged in production.

## Changes

- Keep the player as the remote-input owner while recommendations are open. Move the highlighted recommendation in player state; Back and Up close the panel, and Select plays the highlighted video. Card rendering no longer requires native focus to respond.
- Prevent the scheduled SponsorBlock focus handoff from taking control while any player panel is open. Disable its Skip button during the panel, then restore Skip focus after the final panel closes if the prompt is still active.
- Give Description and Comments Close buttons explicit default focus and a cancellable handoff when their panels open.
- Host the deterministic UI fixture inside TabView → NavigationStack → player, matching the normal app's navigation topology. The earlier tests hosted PlayerView directly and did not exercise this handoff.

## Validation

The focused recommendations run passed 140 unit tests across 14 suites and 20 simulator UI tests, with zero failures or skips. Source: `tmp/recommendations-final-focused.log` and `tmp/native-tvos-tests.BcwoNT/settings.json`.

After adding Description and toast ownership, `just test-native-tvos` passed 140 unit tests and 22 simulator UI tests, zero failures or skips. Source: `tmp/player-panel-focused-final.log` and `tmp/native-tvos-tests.U8iFV9/settings.json`. Comments was added afterward and receives a separate scoped regression run.

The final Comments patch passed four scoped UI checks with zero failures or skips: Comments Back, repeated Description Back, Description Close with a delayed toast, and recommendations with a delayed toast. Source: `tmp/player-panels-with-comments-green-summary.json` and its xcresult bundle. No new unit tests were added for view focus.

Independent review found no remaining correctness defects. Secrets, documentation links and strict formatting passed. `just ci` stops at 143 lint violations, including two newly unmasked file-length alerts in the already oversized ControlElements and Overlays files. The lint baseline was not expanded. Source: `tmp/player-panels-with-comments-ci.log`. This is not a passing full repository gate.

These tests establish remote actions and state transitions using deterministic metadata without media loading. The Comments fixture skips network loading and exercises the empty panel. They do not prove physical Siri Remote timing, live YouTube playback, real comment responses, or the absence of every focus race. Physical acceptance requires repeatedly opening recommendations, navigating both directions, closing with Up and Back, and opening Description and Comments from More and closing them with Back while watching a real video.

## Why the current route stops at 1080p

The VisionOS HLS policy caps height at 1080 and admits H.264/AVC (`avc1`) variants. Sources: `InnerTubeClients.swift`, `PlaybackViewModel+Fallback.swift` and `HLSManifestParser.swift`.

An anonymous watch-seeded VisionOS probe for the reported video `CyEoXiiZZgc` returned a playable master manifest containing 17 variants. Its 2160p variant uses `vp09.00.50.08`; its highest AVC variant is 1080p (`avc1.640028`). No 2160p AVC, HEVC or AV1 variant was present in that response. Source: `tmp/visionos-hls-4k-probe-corrected-CyEoXiiZZgc.json`. This is a time-specific measurement of one video and client response, not a claim about all YouTube videos.

Removing the height cap alone would still exclude that video's 4K VP9 variant. A 4K change needs a separately verified VP9 player route or a client response supplying compatible 4K AVC/HEVC. This focus patch does not change stream selection or decoding policy.
