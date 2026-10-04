#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd -- "$repo_root"
mkdir -p tmp
report_dir="$(mktemp -d "$repo_root/tmp/native-tvos-tests.XXXXXX")"
unit_filter='(^|\.)(SponsorBlockSkipManagerTests|SponsorBlockDecisionEngineTests|PlaybackSeekingTests|PlaybackDiagnosticsTests|PlaybackItemFailureTests|WatchHistoryAuthTokenTests|WatchtimeTrackerOverlapTests|CaptionsManagerTests|PlaybackQualityTests|SettingsQualityPersistenceTests)/'

just --command swift test --package-path SmartTubeIOS --filter "$unit_filter" 2>&1 | tee "$report_dir/unit.log"
just --command python3 - "$report_dir/unit.log" <<'PY'
import pathlib
import re
import sys

log = pathlib.Path(sys.argv[1]).read_text()
result = re.search(r'Test run with (\d+) tests? in (\d+) suites? passed', log)
if result is None or int(result[1]) == 0 or 'skipped' in log.lower():
    raise SystemExit('Native unit checks must execute tests and pass without skips.')
PY

just --command xcodebuild test \
    -workspace SmartTube.xcworkspace \
    -scheme 'Smart Tube' \
    -destination "platform=tvOS Simulator,name=${SMARTTUBE_TV_SIM:-Apple TV}" \
    -derivedDataPath "${SMARTTUBE_DERIVED_DATA:-$repo_root/DerivedData/SmartTube}" \
    -resultBundlePath "$report_dir/settings.xcresult" \
    -parallel-testing-enabled NO \
    -only-testing:SmartTubeTVUITests/TVSettingsUITests \
    CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY= CODE_SIGN_STYLE= \
    DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= \
    -quiet 2>&1 | tee "$report_dir/settings.log"

just --command xcrun xcresulttool get test-results summary \
    --path "$report_dir/settings.xcresult" > "$report_dir/settings.json"
just --command python3 - "$report_dir/settings.json" <<'PY'
import json
import pathlib
import sys

summary = json.loads(pathlib.Path(sys.argv[1]).read_text())
if summary['result'] != 'Passed' or summary['passedTests'] == 0 or summary['failedTests'] or summary['skippedTests']:
    raise SystemExit('Native Settings checks must execute tests and pass without skips.')
print(f"Settings: {summary['passedTests']} passed, zero failures or skips.")
PY

printf 'Native checks passed. Reports: %s\n' "$report_dir"
