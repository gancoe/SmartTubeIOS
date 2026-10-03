# SmartTube Native for Apple TV

This personal fork aims to provide MuTube-like Home, subscriptions, search,
Google sign-in, ad-free playback and SponsorBlock through native tvOS screens
and AVPlayer playback. Keep the existing MuTube installation until the trial
passes on Apple TV hardware.

## Build

Install Xcode with the tvOS SDK, accept its licence yourself, and install `just`.
Commit source changes first so the release records a reproducible source commit.
From the repository root:

```sh
just build-native-tvos
```

The build uses the existing `Smart Tube` target with a separate identity:

- Display name: `SmartTube Native`.
- Bundle identifier: `com.gancoe.smarttube.tv`.
- Output: a new directory under `releases/` containing `SmartTubeNative-tvOS.ipa`,
  its SHA-256 and source provenance. Failed builds preserve prior releases.
- Signing: unsigned. The IPA must be signed through ATVLoadly before device use.
- Firebase: the tvOS upload phase is removed and startup leaves Crashlytics
  disabled when no `GoogleService-Info.plist` is bundled. Do not add the original
  developer's credentials or a fabricated Firebase configuration.

A manual **Native tvOS IPA** GitHub Actions template is saved at
`docs/examples/native-tvos-workflow.yml`. To enable it later, copy it into
`.github/workflows/` using a GitHub credential with `workflow` permission.
It builds the same artifact; it does not install an app or prove that playback
works on a television.

## Validation

```sh
just ci
just build-tvos
just test-tvos-settings
```

The existing Settings UI suite may skip tests when it cannot navigate to the
screen. Check executed, passed, failed and skipped counts, not just the process
exit status. Simulator launch and Settings tests do not prove video decoding,
ad-free playback, Google sign-in or watch-history syncing.

Baseline inspection on 2026-10-04 found inherited lint violations in pristine
upstream commit `bb724e28cb05cca7e7da95c5b2e8d657ccc7ee03`. The native macOS unit
suite also needed PNG conversion and web-view callback compile fixes before
its tests could execute. The full unit suite still has failures; a successful
tvOS archive must not be presented as a passing repository quality gate.

## Apple TV acceptance

Install alongside MuTube through ATVLoadly, then verify:

1. The app opens with the physical Siri Remote and its Home feed loads.
2. Google device-code sign-in succeeds through the normal activation screen.
3. Personalised Home and subscriptions match the signed-in account.
4. Playback, audio, seeking, resume, captions and desired resolution work.
5. SponsorBlock skips a video with a known segment and ordinary playback has
   no pre-roll or mid-roll advertisements.
6. A watched video appears in the account's history in the normal YouTube UI.
7. The app survives a signing refresh and can be used without recovery help.

Do not export or inspect Google OAuth tokens during this validation. Preserve
the existing sideloading, browser relay and SponsorBlock fallback services.
