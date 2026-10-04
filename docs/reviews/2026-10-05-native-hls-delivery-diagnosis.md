# Native HLS delivery diagnosis, 2026-10-05 NZ time

## Outcome

No playback fix is established. Automatic physical-TV capture is working. The new change preserves a canonical `HTTP NNN` status from native error comments, alongside existing timeout messages, without transmitting the original comment or changing player behavior.

## Measured evidence

- `tmp/hls-selfhost-captured-events.json`, retrieved 2026-10-04 11:04 UTC: video `PEY61MOv950` had errors without a manual seek, including a first no-response event at position zero before accelerated playback. That rules out seeking or accelerated consumption as necessary triggers, but not contributing factors.
- That video entered 144p at 10:47:01 UTC and subsequently recorded `-12889`, `-15628` and `-16840`. Current samples do not identify the actual HTTP response behind the latter events because their native comments were redacted.
- Fresh signed rendition requests from the Mac and Pi completed successfully. The steady-video Mac replay downloaded tested 2160p, 1080p and 240p segments in under 0.576 s (`tmp/delivery-replay-PEY61MOv950-mac.json`). These are fresh request controls, not the TV's failed requests, so they do not eliminate intermittent CDN or session failures.
- A Mac native AVPlayer harness reproduced `-16840` with `HTTP 401` in its native error comment. An unfiltered custom-scheme run also failed (`tmp/native-delivery-replay/evidence-unfiltered-short.jsonl`). Manifest filtering is therefore not required for that Mac failure.
- The 30 s direct-master run progressed at 1.5× without errors (`evidence-direct-short.jsonl`). A subsequent filtered adapter run also progressed without errors (`evidence-steady-short.jsonl`). The difference is intermittent and does not establish an adapter defect. The short filtered output was overwritten by this rerun; the earlier failure is not retained in that file.
- Headless Mac AVPlayer stayed at 144p even during clean runs. Decoded codec identification was unavailable. This harness establishes native request failure evidence, not physical-TV 4K behavior or decoder parity.
- Foundation URLSession audio controls returned HTTP 200, including HTTP/3 and byte-range requests (`tmp/native-urlsession-audio-context.json`). This does not identify the CoreMedia request context that failed.
- By 11:04:23 UTC the TV was playing a different video at 4K and 1.5× without errors. Recovery or a clean different video is not acceptance of a fix.

## Hypotheses and next gate

The TV root cause remains **UNVERIFIED**. Intermittent media delivery, a native request context difference, and accelerated buffer consumption remain possible contributors. Constant media unavailability is weakened by successful replay controls; seeking and accelerated consumption alone cannot explain the pre-playback no-response event. The active Native4K master uses the current URL, so a stale picker variant cache is not a demonstrated explanation.

Capture the TV's canonical HTTP status on the next failure. If it reports 401, compare the failing signed resource and request context through a private local harness; if it reports only a no-response timeout, obtain native request timing and protocol before changing quality policy. Do not infer HTTP status solely from a CoreMedia error number.

Keep diagnostics separate from cache changes and bitrate or quality constraints. Acceptance of a playback fix requires matched device playback at 1.5× and 2×, sustained quality, and absence of the reproduced failure across repeated videos. Hermetic policy tests cannot establish that result.

## Logging validation

The new HTTP comment tests first failed against the old implementation, then passed after the narrow sanitizer and collector allowlist change. Focused Swift diagnostics: 21 tests in three suites passed (`tmp/http-status-green-final.log`). Collector: 11 tests passed (`tmp/http-status-green-python.log`). Full `just ci` stopped at the inherited 148 lint violations (`tmp/http-status-ci.log`); a green full gate is not claimed.
