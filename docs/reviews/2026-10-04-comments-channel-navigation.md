# Apple TV comments and creator navigation

Date: 2026-10-04
Scope: personal `gancoe/SmartTubeIOS` fork, `native-tvos` branch; issues [#4](https://github.com/gancoe/SmartTubeIOS/issues/4) and [#5](https://github.com/gancoe/SmartTubeIOS/issues/5).

## Diagnosis

The user confirmed that the previous panel dismissal patch works, then reported that comments could not scroll or open reply threads and that the creator profile was unavailable.

Comments originally rendered plain rows without a remote selection model. Adding focusable rows and then native buttons did not resolve the populated panel's focus handoff: the simulator could not focus its Close button or navigate into rows. Sources: `tmp/comments-scroll-red.xcresult`, `tmp/comments-scroll-green-summary.json`, `tmp/comments-navigation-green2-summary.json`, and `tmp/comments-focus-reset.xcresult`. The alternative of unavailable comment data is insufficient because synthetic populated comments reproduce the failure without network access.

The old comments API discarded page and reply continuations. An anonymous WEB `/next` probe returned parent threads, nested reply continuations and a reply response with entity-backed comments. Source: `tmp/comments-replies-probe-CyEoXiiZZgc.json`. The probe records structural keys and counts, not comment text, authors or raw tokens. The alternative that YouTube never exposes replies is ruled out for that measured response; it is not a guarantee of every video's availability.

The `/player` parser discarded `videoDetails.channelId`, while the existing creator action requires a nonempty ID. Sources: `InnerTubeAPI+Player.swift` and `PlayerView+ControlElements.swift`. Parser regressions verify present, absent and blank IDs. The alternative that channel browsing is entirely unimplemented is ruled out by the existing ChannelView and the passing synthetic creator-page navigation test.

## Changes

- Keep the player as the Siri Remote input owner while Comments is open. Up and Down select exactly one item and scroll it into view. Selected items, Close, Load more and Retry have a visible background and white border.
- Select opens a comment's replies. Back returns to the parent list and restores its selection; a second Back closes Comments. Moving to another video dismisses the old thread, and reopening Comments loads the current video ID.
- Parse ordered parent comments separately from replies, supporting entity and legacy responses. Preserve independent page continuations, inline replies and reply counts.
- Fetch more comments or replies only on request. Deduplicate IDs, preserve loaded content on failures, retry the same continuation, cache opened threads, and ignore late completions after a video switch.
- Preserve creator IDs from player metadata. Pass the player's configured API into channel browsing, nested channel routes and the selected video. A supplied concrete playback client is retained; default callers keep the environment playback client. Start channel focus on its first visible video and expose each card as one accessible selectable item.
- Keep deterministic comment/channel content and the video-advance trigger behind DEBUG/tvOS guards. Disable card network prewarming in the player UI fixture.

MuTube is an interaction reference, not a source of copied implementation. Its [repository](https://github.com/Exaphis/mutube) describes patching the existing YouTube TV app. The benchmark here is visible selection, predictable directional input, selecting a thread or video, and Back returning one level. These changes retain the native SwiftUI/AVPlayer architecture and do not change codec selection, playback recovery or the current 1080p policy.

## Validation

Two scoped simulator tests pass for comments scrolling and thread Back. Source: `tmp/comments-navigation-green3-summary.json` (the separate creator test in that run failed before the final focus change).

Four subsequent scoped tests pass, with zero failures or skips: comment/reply pagination with the remote, retry after a reply failure, dismissal of an old thread when playback advances, and creator-page video selection plus return to the channel. Source: `tmp/comments-pages-channel-summary.json`.

The focused unit portion passes 159 tests across 18 suites. Source: `tmp/comments-channel-native-final.log`. The full simulator portion passes 29 tests with zero failures or skips. Source: `tmp/native-tvos-tests.SjYXlv/settings.json`.

The final channel client-handoff correction passes the creator navigation simulator test again. Source: `tmp/comments-channel-handoff-final-summary.json`. Independent review found no outstanding concrete defect after that correction.

`just ci` passes secrets, documentation links and strict formatting, then stops at 144 SwiftLint violations. The previous panel patch recorded 143; changing the oversized player parser's visibility for a real parser test newly exposes its existing function-length violation. New files and additions were cleaned up without expanding the lint baseline. Source: `tmp/comments-channel-ci-final.log`. This is not a passing full repository gate. No physical Apple TV installation or acceptance is claimed for this patch yet. Simulator UI fixtures establish navigation and state changes without live media decoding; physical focus timing, live comment availability and playback remain separate checks.
