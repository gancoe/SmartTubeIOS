# Automatic playback capture on the home rig

## Scope

This isolated diagnostics candidate extends `9f23dc7` and does not change stream selection, quality limits, playback speed, recovery or prefetching. The separately prepared cache fix remains separate.

The player samples its existing native item every two seconds while the player view is present. It emits state changes, a 15-second heartbeat, and every newly observed native error-log entry. Each record contains capture time, native error time, video ID, playback position, resolution, playback rate, media/viewing buffer, advertised/observed bitrate, transferred bytes, stalls and dropped frames. Error resource classification is a URL hint, not proof of the exact failed request. Captured resolution/buffer describe sampling time rather than the historical error timestamp.

Raw URLs, signed queries, credentials and arbitrary native error comments are excluded. Known timeout comments are allowed; other comments remain redacted. The video ID is retained to reproduce the affected video.

## Delivery and separation

No bundled configuration means no remote reporting. The configured diagnostic IPA posts to the explicitly selected LAN receiver using a private bearer token. Credentials are packaged locally and must not be published with an IPA. The bundle permits HTTP only for that configured host and supplies the local-network permission explanation.

The sender stores at most 1,000 pending events or 1 MiB, retries later after a failed send, deduplicates event IDs and serializes flush operations. Queue writes are atomic. Sending uses an ephemeral URLSession with two-second request timeout; it does not create media assets or alter the player. Reporting stops when the player view disappears.

The separate non-root, read-only Docker service stores at most 10,000 validated records in its named data volume. Host binding is explicitly the Pi's LAN address on port 8765. Other services are not restarted. The authenticated read API allows analysis without screenshots.

## Acceptance and rollback

Unit and loopback integration checks do not establish physical Apple TV delivery. Deployment acceptance requires a successful installer refresh of the exact IPA followed by a native event received from that TV. A local-network permission prompt may require the remote once. The prior installed IPA remains the rollback; stop only the new collector service to disable receiving without touching existing services. The data volume is retained by `docker compose down` unless `--volumes` is requested.

This captures the `-16830` timeout and quality transitions. It does not establish or fix the underlying delivery failure. The next diagnosis compares timeout timing with quality, playback speed and buffer across repeated videos, then changes one delivery behavior at a time.

## Measured validation, 2026-10-04

- Focused playback/diagnostics package run: 123 tests in 11 suites passed (`tmp/hls-selfhost-focused-final.log`).
- Collector: 10 tests passed; packaging: three tests passed.
- Actual Swift URLSession sender to Python receiver: one synthetic timeout accepted, queue empty after acknowledgement, position/speed/bitrate fields verified (`tmp/hls-selfhost-integration.json`). This was Mac loopback, not the physical TV.
- Independent review identified mismatched whitespace token validation; client and packaging validation now reject whitespace consistently with the collector.
- `just ci` passed secrets, documentation links and formatting, then stopped at the existing 148 lint violations (`tmp/hls-selfhost-ci.log`). It did not reach its full unit-test stage. The focused suite was run separately; a clean full CI gate is not claimed.
- Pi collector deployed in a separate Docker Compose project after the user authorized interruption and installation. LAN health returned HTTP 200 before any TV event. This verifies the service, not physical app capture.
