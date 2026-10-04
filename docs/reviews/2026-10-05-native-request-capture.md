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

- Focused Swift diagnostics: 39 tests in 6 suites passed, including the actual
  monitor cancellation test with blocked delivery, expiry, replacement, stale
  errors, duplicate attachment and persistent bounds. Log:
  `tmp/native-metrics-client-tests.log`.
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
  `tmp/native-metrics-ci.log`, `tmp/native-metrics-base-lint.log`.

The receiver now permits safe `resource_request_duration_seconds` even when
transaction response metrics are absent. It still rejects that duration if the
resource event itself is absent. This is the native resource request interval,
not an inferred transaction response time.

No physical native-metric capture or playback improvement has been established
by these tests. The separately saved Stats for Nerds dismissal patch remains
outside this diagnostic change.
