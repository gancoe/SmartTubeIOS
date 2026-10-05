# Yattee playback comparison, 5 October 2026

Current public source was inspected read-only. No Yattee code or dependency was incorporated. No Yattee physical playback comparison was performed, so relative reliability remains UNVERIFIED.

## Useful patterns

1. [MPV cache setup](https://github.com/yattee/yattee/blob/main/Yattee/Services/Player/MPV/MPVClient.swift#L533-L547): tvOS cache time and byte limits are distinct (30-second cache preference, 20-second readahead, 24 MiB forward and 8 MiB backward budgets). The byte ceiling can bind before the time target. Do not copy these values into AVPlayer as equivalent guarantees.
2. [Startup and seek gate](https://github.com/yattee/yattee/blob/main/Yattee/Services/Player/MPVBackend.swift#L630-L729): wait on measured cache readiness with a timeout before playback; [PlayerService](https://github.com/yattee/yattee/blob/main/Yattee/Services/Player/PlayerService.swift#L544-L563) invokes the gate. Observable buffer state is a stronger diagnostic than a preference alone. The timeout can still allow short-buffer playback.
3. [Hardware capability checks](https://github.com/yattee/yattee/blob/main/Yattee/Core/HardwareCapabilities.swift#L61-L117) are separate from [VideoToolbox MPV configuration](https://github.com/yattee/yattee/blob/main/Yattee/Services/Player/MPV/MPVClient.swift#L460-L466). Our capability query does not establish the selected codec or active decoder; these should remain distinct reported facts.
4. [Quality selection](https://github.com/yattee/yattee/blob/main/Yattee/Views/Player/QualitySelectorView+StreamHelpers.swift#L9-L117) distinguishes adaptive HLS/DASH from individual ranked stream choices. A max-resolution preference is not a quality lock. A future fixed-quality comparison must retain audio and report its stall tradeoff.
5. [HTTP header propagation](https://github.com/yattee/yattee/blob/main/Yattee/Services/Player/MPV/MPVClient.swift#L675-L750) explicitly disables an EDL fast path when required headers cannot be propagated correctly. This is a reusable correctness principle, not evidence that our native HTTP-200 delay is a header failure.

[Playback speed](https://github.com/yattee/yattee/blob/main/Yattee/Services/Player/MPVBackend.swift#L36-L45) sets MPV speed directly. This does not establish speed-scaled buffering or reliable 4K at 2× on our device.

## Recommendation

Finish the isolated AVPlayer 100-second buffer experiment. If slow completion and quality changes persist, prepare a separate minimal MPV comparison using the same affected video and as closely matched a source as possible. Record differences in extraction/client profile and network path rather than attributing all differences to the engine. Verify actual hardware decode, 1.5×/2× continuity, audio, seeking and remote controls before replacing any existing implementation. MPV and VLC are viable tvOS alternatives; integration and packaging maturity require separate review.

A source audit cannot establish that starting with Yattee would have produced a better outcome. It does establish that an earlier engine and stream-selection comparison would have been useful.
