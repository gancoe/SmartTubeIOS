# Bounded physical-tvOS request capture

## Decision and scope

Jonathan authorised Astra review followed by implementation. Astra approved this
revised diagnostic plan on 5 October 2026: capture native HLS segment requests
and completed variant switches in the actual app, based on installed source
`e8a275dc1ef3141a6dd031c12806d0688b8d1a5e`. Keep playback tuning, cache work and
the saved Stats for Nerds dismissal patch separate. Approval is for diagnosis,
not a claim that the playback issue is fixed.

The root cause remains UNVERIFIED. Recorded timeout errors and resolution drops
can coincide, but some resolution drops occur without a new error. Native
adaptive playback can recover without stalling. Neither a log error nor a
successful Mac replay establishes the cause on the physical Apple TV.

## Hypotheses and distinguishing evidence

1. A native media request exceeds its delivery deadline and triggers a lower
   variant. Capture the failing request's available status and timings before
   the completed switch. Successful requests without a new error weaken this
   explanation for that particular drop.
2. The HLS adapter contributes through playlist selection or repair. A later
   comparison must hold surviving variants, audio groups and segment URI
   targets constant before changing the adapter path.
3. Accelerated playback consumes buffer faster and aggravates delivery gaps.
   Compare request duration and viewing buffer at the requested 1.5–2× speed.
   Earlier startup failures show accelerated playback is not a necessary cause.

Astra rejected a standalone Mac-filtered master as a decisive adapter A/B test:
the app also filters audio language and repairs child playlist durations. The
two paths were not yet equivalent. A separate test application would introduce
additional signing and playback-policy differences. Capture in the app first.

## Approved capture

- Explicit opt-in configuration with one random capture UUID. No configuration
  means no native subscription.
- Stop after the first explicit `-16830` or `-12889` and a 60-second recovery
  window, or after 30 minutes. Persist the deadline so relaunch cannot extend it.
- Subscribe once per current player item. Cancel promptly on replacement,
  shutdown, task cancellation and expiry; reject late events from old items.
- Correlate safe metrics with capture and item generation UUIDs, report/video
  IDs, timestamps and playback position.
- Send only whitelisted media type, itag, map flag, duration, availability/cache
  flags, safe error domain/code, and at most eight transaction summaries.
  Transaction summaries contain status, protocol, connection reuse and timing.
  Completed switches contain success, dimensions and bitrates.
- Missing resource or transaction metrics mean unavailable. An absent response
  alone is not evidence of a timeout. Never serialize URLs, credentials,
  headers, raw errors or native metric objects.
- Bound queued events and delivery work; report dropped diagnostic events.
  Do not change playback, buffering, selection, request headers, caching or UI.

## Acceptance

Before installation: compile tvOS; test nil metrics, redaction, bounded queues,
cancellation and rejection of stale events; verify collector backward
compatibility. Retain the installed IPA and hash, verify the installer queue is
empty, and verify the replacement installation by its retained IPA hash and
refreshed app record. Do not publish configured IPAs containing the collector
credential.

Run one affected video at Jonathan's normal accelerated speed, initially without
seeking. After the bounded capture:

- Failed native requests preceding a downgrade justify investigating the
  specific request class, status and timing.
- A completed downgrade with successful requests and no new error is adaptation
  evidence to investigate separately.
- Missing metrics or no reproduction is inconclusive. Do not extend capture
  indefinitely or call the issue fixed.

The receiver's synthetic roundtrip proves transport and schema acceptance only.
Physical-device evidence is a separate acceptance gate.

## Implementation verification on 5 October 2026

Astra's final code review approved the diagnostic installation, conditional on
compilation and the parent installation checks. Earlier review findings about
contradictory receiver fields, owner cancellation, duplicate subscriptions,
stale callbacks, native timestamps, missing request duration, itag parsing and
persistent bounds were corrected before this approval.

Measured commands in this run:

- Focused Swift diagnostics: 42 tests in 6 suites passed, including the actual
  monitor cancellation test with blocked delivery, expiry, replacement, stale
  errors, duplicate attachment and persistent bounds. Log:
  `tmp/native-metrics-client-tests-final.log`.
- Receiver standard-library tests: 20 passed. Log:
  `tmp/native-metrics-receiver-final.log`.
- Configuration tests: 5 passed.
- `just build-tvos`: exited successfully. Log:
  `tmp/native-metrics-tvos-build.log`.
- `just ci`: secrets and format checks passed; lint failed with 150 serious
  violations. A fresh archive of baseline HEAD was independently linted and
  measured 148 violations. Length checks in the existing loading file differ
  after adding diagnostic lifecycle hooks. The baseline was not changed; this
  is not a green full-repository gate. Logs:
  `tmp/native-metrics-ci-final.log`, `tmp/native-metrics-base-lint.log`.

Astra approved the final persistence change after read-only review. Production
tvOS stores only capture UUID, start, deadline and state in `UserDefaults.standard`,
Apple's persistent settings store. The injectable file backend remains for
failure tests and other platforms. Isolated defaults suites verify reopening,
ended captures and malformed state. Settings readback verifies acceptance,
not synchronous disk durability. The earlier `de0bf22` IPA is superseded and
must not be installed.

The receiver now permits safe `resource_request_duration_seconds` even when
transaction response metrics are absent. It still rejects that duration if the
resource event itself is absent. This is the native resource request interval,
not an inferred transaction response time.

No physical native-metric capture or playback improvement has been established
by these tests. The separately saved Stats for Nerds dismissal patch remains
outside this diagnostic change.

## Installed build and shutdown handoff, 5 October 2026 NZ time

Measured installation source: `4cb22a6860e5b667f203d91adced8232ef14c49f`.
The final tvOS Release archive succeeded. The packaged private configuration
matched the prepared capture configuration. ATVLoadly reported a successful
replacement of app record 4, with an empty queue and a retained unsigned IPA
whose SHA-256 matched:

`66f36c6ac2085d7e1c7fe8de5956ea0f4ac2528f346f211bdd2c594d557b9b6c`

Local evidence: `tmp/native-metrics-release-verification.json` and
`tmp/native-metrics-install-verification.json`. These records were rechecked
at shutdown. Later documentation commits do not change the installed app.
The rollback IPA from source `e8a275dc1ef3141a6dd031c12806d0688b8d1a5e`
was retained and rehashed successfully:

`2b0b43b50f9ee718b1e89266038b185f72ea4c78728342b856dff0c371711b7b`

The Pi receiver accepts the new native schema and existing logs. Its synthetic
roundtrip passed, but a shutdown check found zero physical events for the new
capture UUID. Ordinary earlier playback logs are separate from this new
native-metric acceptance gate. The playback cause and any improvement remain
UNVERIFIED.

Resume with one affected video at 1.5–2×, initially without seeking. Read the
matching capture UUID from the private configuration and retrieve the Pi's
events. The local ignored helper `tmp/check-native-device-capture.py` provides
a safe compact summary; it does not start or renew a capture. Verify actual
native segment and completed-switch events before analysing the failure.
Allow the capture's existing bound to end; do not silently reset its UUID or
deadline. Missing metrics or failure to reproduce is an inconclusive result.

Keep [PR #12](https://github.com/gancoe/SmartTubeIOS/pull/12) in draft until this
device gate is assessed. Do not mix in [Stats Back dismissal #11](https://github.com/gancoe/SmartTubeIOS/pull/11)
or [cache invalidation #7](https://github.com/gancoe/SmartTubeIOS/pull/7).
Those separate branches were not installed in this build.

The user can leave the Apple TV off. No Mac replay harness or ongoing Mac
capture is needed overnight. The Pi collector remains available for the next
playback test. Configured IPAs and credentials stay private.
