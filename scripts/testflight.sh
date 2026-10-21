#!/bin/bash
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="/Applications/Xcode_$(tr -d '\r\n' < .xcode-version).app/Contents/Developer"
UPLOAD_TO_TESTFLIGHT="${UPLOAD_TO_TESTFLIGHT:-false}"
case "$UPLOAD_TO_TESTFLIGHT" in true|false) ;; *) echo 'Invalid upload flag'; exit 1 ;; esac
for name in APPLE_TEAM_ID DISTRIBUTION_P12_BASE64 DISTRIBUTION_P12_PASSWORD \
  PHONE_PROFILE_BASE64 WATCH_PROFILE_BASE64 COMPLICATION_PROFILE_BASE64 \
  BUILD_NUMBER \
  ALARM_BEANS_BUNDLE_ID ALARM_BEANS_APP_GROUP; do
  if [ -z "${!name:-}" ]; then
    echo "::error::Missing release setting: $name"
    exit 1
  fi
done
if [ "$UPLOAD_TO_TESTFLIGHT" = true ]; then
  for name in ASC_KEY_ID ASC_ISSUER_ID ASC_PRIVATE_KEY_BASE64; do
    if [ -z "${!name:-}" ]; then echo "::error::Missing upload setting: $name"; exit 1; fi
  done
fi

umask 077
release_dir="$(mktemp -d "$RUNNER_TEMP/alarmbeans-signing.XXXXXX")"
keychain="$release_dir/signing.keychain-db"
keychain_password="$(openssl rand -hex 32)"
profile_dir="$HOME/Library/MobileDevice/Provisioning Profiles"
mkdir -p "$profile_dir"

cleanup() {
  security delete-keychain "$keychain" >/dev/null 2>&1 || true
  if [ -f "$release_dir/profile-paths.txt" ]; then
    while IFS= read -r profile_path; do rm -f "$profile_path"; done < "$release_dir/profile-paths.txt"
  fi
  rm -rf "$release_dir"
}
trap cleanup EXIT

printf '%s' "$DISTRIBUTION_P12_BASE64" | base64 --decode > "$release_dir/distribution.p12"
security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$release_dir/distribution.p12" -P "$DISTRIBUTION_P12_PASSWORD" -A -t cert -f pkcs12 -k "$keychain" >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain" >/dev/null
security list-keychains -d user -s "$keychain"

for kind in PHONE WATCH COMPLICATION; do
  variable="${kind}_PROFILE_BASE64"
  printf '%s' "${!variable}" | base64 --decode > "$release_dir/$kind.mobileprovision"
  security cms -D -i "$release_dir/$kind.mobileprovision" > "$release_dir/$kind.plist"
  profile_uuid="$(/usr/libexec/PlistBuddy -c 'Print :UUID' "$release_dir/$kind.plist")"
  profile_name="$(/usr/libexec/PlistBuddy -c 'Print :Name' "$release_dir/$kind.plist")"
  cp "$release_dir/$kind.mobileprovision" "$profile_dir/$profile_uuid.mobileprovision"
  printf '%s\n' "$profile_dir/$profile_uuid.mobileprovision" >> "$release_dir/profile-paths.txt"
  export "ALARM_BEANS_${kind}_PROFILE=$profile_name"
done

bash scripts/bootstrap.sh
xcodebuild -project AlarmBeans.xcodeproj -scheme AlarmBeans -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/AlarmBeans.xcarchive \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY='Apple Distribution' CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  ALARM_BEANS_BUNDLE_ID="$ALARM_BEANS_BUNDLE_ID" ALARM_BEANS_APP_GROUP="$ALARM_BEANS_APP_GROUP" \
  ALARM_BEANS_PHONE_PROFILE="$ALARM_BEANS_PHONE_PROFILE" \
  ALARM_BEANS_WATCH_PROFILE="$ALARM_BEANS_WATCH_PROFILE" \
  ALARM_BEANS_COMPLICATION_PROFILE="$ALARM_BEANS_COMPLICATION_PROFILE" archive

export EXPORT_OPTIONS_PATH="$release_dir/ExportOptions.plist"
python3 - <<'PY'
import os, plistlib
bundle = os.environ['ALARM_BEANS_BUNDLE_ID']
options = {
    'method': 'app-store-connect',
    'destination': 'export',
    'teamID': os.environ['APPLE_TEAM_ID'],
    'signingStyle': 'manual',
    'signingCertificate': 'Apple Distribution',
    'manageAppVersionAndBuildNumber': False,
    'uploadSymbols': True,
    'provisioningProfiles': {
        bundle: os.environ['ALARM_BEANS_PHONE_PROFILE'],
        bundle + '.watchkitapp': os.environ['ALARM_BEANS_WATCH_PROFILE'],
        bundle + '.watchkitapp.waketime': os.environ['ALARM_BEANS_COMPLICATION_PROFILE'],
    },
}
with open(os.environ['EXPORT_OPTIONS_PATH'], 'wb') as f:
    plistlib.dump(options, f)
PY
xcodebuild -exportArchive -archivePath build/AlarmBeans.xcarchive \
  -exportPath build/Export -exportOptionsPlist "$EXPORT_OPTIONS_PATH"

if [ "$UPLOAD_TO_TESTFLIGHT" != true ]; then
  echo 'Prepared signed IPA; TestFlight upload disabled.'
  exit 0
fi

mkdir -p "$release_dir/private_keys"
printf '%s' "$ASC_PRIVATE_KEY_BASE64" | base64 --decode > "$release_dir/private_keys/AuthKey_$ASC_KEY_ID.p8"
ipa="$(find "$PWD/build/Export" -maxdepth 1 -name '*.ipa' -print -quit)"
test -n "$ipa"
cd "$release_dir"
xcrun altool --upload-app --type ios --file "$ipa" --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
