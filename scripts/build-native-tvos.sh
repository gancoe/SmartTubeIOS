#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
workspace="${SMARTTUBE_WORKSPACE:-$repo_root/SmartTube.xcworkspace}"
scheme="${SMARTTUBE_TV_SCHEME:-Smart Tube}"
diagnostics_config="${SMARTTUBE_DIAGNOSTICS_CONFIG:-}"
release_dir="${SMARTTUBE_NATIVE_TV_RELEASE_DIR:-$repo_root/releases}"
[[ "$workspace" = /* ]] || workspace="$repo_root/$workspace"
[[ "$release_dir" = /* ]] || release_dir="$repo_root/$release_dir"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/smarttube-native-tvos.XXXXXX")"
archive_path="$work_dir/SmartTubeNative-tvOS.xcarchive"
derived_data_path="${SMARTTUBE_NATIVE_TV_DERIVED_DATA:-$repo_root/DerivedData/NativeTV}"
staging_dir="$work_dir/staging"
output_work_dir=""
build_settings_file="$work_dir/native-tvos.xcconfig"

cleanup() {
    rm -rf -- "$work_dir"
    [[ -z "$output_work_dir" ]] || rm -rf -- "$output_work_dir"
}
trap cleanup EXIT

die() {
    printf 'build-native-tvos: %s\n' "$*" >&2
    exit 1
}

git -C "$repo_root" rev-parse --show-toplevel >/dev/null 2>&1 || die "repository root is not a Git checkout: $repo_root"
[[ -z "$(git -C "$repo_root" status --porcelain)" ]] || die "commit changes before building a release so its source commit is reproducible"
[[ -d "$workspace" ]] || die "workspace not found: $workspace"
command -v xcodebuild >/dev/null 2>&1 || die "xcodebuild is required"
command -v plutil >/dev/null 2>&1 || die "plutil is required"
command -v zip >/dev/null 2>&1 || die "zip is required"
command -v shasum >/dev/null 2>&1 || die "shasum is required"

mkdir -p -- "$release_dir"
output_work_dir="$(mktemp -d "$release_dir/.native-tvos.XXXXXX")"
release_path="$release_dir/SmartTubeNative-tvOS-$(git -C "$repo_root" rev-parse --short=12 HEAD)-${output_work_dir##*.}"
ipa_path="$release_path/SmartTubeNative-tvOS.ipa"
staged_ipa_path="$output_work_dir/SmartTubeNative-tvOS.ipa"
staged_sha_path="$staged_ipa_path.sha256"
staged_provenance_path="$staged_ipa_path.provenance.txt"

printf '%s\n' \
    'CODE_SIGN_IDENTITY =' \
    'CODE_SIGN_IDENTITY[sdk=appletvos*] =' \
    'CODE_SIGN_STYLE =' \
    'CODE_SIGN_STYLE[sdk=appletvos*] =' \
    'DEVELOPMENT_TEAM =' \
    'DEVELOPMENT_TEAM[sdk=appletvos*] =' \
    'PROVISIONING_PROFILE_SPECIFIER =' \
    'PROVISIONING_PROFILE_SPECIFIER[sdk=appletvos*] =' \
    > "$build_settings_file"

printf 'Building unsigned tvOS archive for scheme %s\n' "$scheme"
xcodebuild archive \
    -workspace "$workspace" \
    -scheme "$scheme" \
    -configuration Release \
    -destination 'generic/platform=tvOS' \
    -archivePath "$archive_path" \
    -derivedDataPath "$derived_data_path" \
    -xcconfig "$build_settings_file" \
    -onlyUsePackageVersionsFromResolvedFile \
    SKIP_INSTALL=NO \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY= \
    CODE_SIGN_STYLE= \
    DEVELOPMENT_TEAM= \
    PROVISIONING_PROFILE_SPECIFIER= \
    PRODUCT_BUNDLE_IDENTIFIER=com.gancoe.smarttube.tv \
    INFOPLIST_KEY_CFBundleDisplayName='SmartTube Native'

app_path="$archive_path/Products/Applications/Smart Tube.app"
[[ -d "$app_path" ]] || die "archive did not contain the expected app: $app_path"
[[ -f "$app_path/Info.plist" ]] || die "built app has no Info.plist: $app_path"

bundle_identifier="$(plutil -extract CFBundleIdentifier raw -o - "$app_path/Info.plist")"
display_name="$(plutil -extract CFBundleDisplayName raw -o - "$app_path/Info.plist")"
[[ "$bundle_identifier" == 'com.gancoe.smarttube.tv' ]] || die "unexpected bundle identifier: $bundle_identifier"
[[ "$display_name" == 'SmartTube Native' ]] || die "unexpected display name: $display_name"
[[ ! -e "$app_path/_CodeSignature" ]] || die "archive unexpectedly contains an app code signature"

if find "$app_path" -name 'GoogleService-Info.plist' -print -quit | grep -q .; then
    die "refusing to package a Firebase GoogleService-Info.plist"
fi

if [[ -n "$diagnostics_config" ]]; then
    command -v python3 >/dev/null 2>&1 || die "python3 is required to configure playback diagnostics"
    python3 "$repo_root/scripts/configure-playback-diagnostics.py" "$diagnostics_config" "$app_path"
fi

mkdir -p -- "$staging_dir/Payload"
ditto "$app_path" "$staging_dir/Payload/Smart Tube.app"
(
    cd -- "$staging_dir"
    zip -qry "$staged_ipa_path" Payload
)

[[ -s "$staged_ipa_path" ]] || die "IPA was not created: $staged_ipa_path"
(
    cd -- "$output_work_dir"
    shasum -a 256 "$(basename "$staged_ipa_path")" > "$(basename "$staged_sha_path")"
)

commit="$(git -C "$repo_root" rev-parse HEAD)"
commit_subject="$(git -C "$repo_root" log -1 --format=%s "$commit")"
working_tree="$(git -C "$repo_root" status --porcelain | tr '\n' ';')"
{
    printf 'artifact: %s\n' "$(basename "$ipa_path")"
    printf 'sha256_file: %s\n' "$(basename "$staged_sha_path")"
    printf 'repository: gancoe/SmartTubeIOS\n'
    printf 'source_commit: %s\n' "$commit"
    printf 'source_commit_subject: %s\n' "$commit_subject"
    printf 'working_tree_at_build: %s\n' "${working_tree:-clean}"
    printf 'workspace: %s\n' "$(basename "$workspace")"
    printf 'scheme: %s\n' "$scheme"
    printf 'configuration: Release\n'
    printf 'destination: generic/platform=tvOS\n'
    printf 'bundle_identifier: %s\n' "$bundle_identifier"
    printf 'display_name: %s\n' "$display_name"
    printf 'signing: unsigned (CODE_SIGNING_ALLOWED=NO, CODE_SIGNING_REQUIRED=NO)\n'
    printf 'device_validation: not performed\n'
    printf 'playback_diagnostics: %s\n' "$([[ -n "$diagnostics_config" ]] && printf configured || printf disabled)"
    printf 'built_at_utc: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
} > "$staged_provenance_path"

mv -- "$output_work_dir" "$release_path"
output_work_dir=""

printf 'IPA: %s\n' "$ipa_path"
printf 'SHA-256: %s\n' "$(cut -d ' ' -f 1 "$ipa_path.sha256")"
printf 'Source commit: %s\n' "$commit"
