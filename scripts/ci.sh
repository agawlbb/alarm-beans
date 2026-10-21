#!/bin/bash
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail
cd "$(dirname "$0")/.."
for script in scripts/*.sh; do bash -n "$script"; done
export DEVELOPER_DIR="/Applications/Xcode_$(tr -d '\r\n' < .xcode-version).app/Contents/Developer"
xcodebuild -version
bash scripts/bootstrap.sh
swift test --package-path Packages/AlarmCore
xcodebuild -project AlarmBeans.xcodeproj -scheme AlarmBeans \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
xcodebuild -project AlarmBeans.xcodeproj -scheme AlarmBeansWatch \
  -destination 'generic/platform=watchOS Simulator' \
  -derivedDataPath build/WatchDerivedData CODE_SIGNING_ALLOWED=NO build
xcodebuild -project AlarmBeans.xcodeproj -scheme AlarmBeans -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/Unsigned.xcarchive \
  -derivedDataPath build/DeviceDerivedData CODE_SIGNING_ALLOWED=NO \
  CURRENT_PROJECT_VERSION=42 MARKETING_VERSION=1.2.3 archive

# Check overrides in all three built bundles to prevent duplicate uploads.
python3 - <<'PY'
import pathlib, plistlib
bundles = [p for p in pathlib.Path('build/Unsigned.xcarchive/Products/Applications').rglob('Info.plist')
           if p.parent.suffix in ('.app', '.appex')]
assert len(bundles) == 3, f'Expected three app/extension bundles, found {len(bundles)}'
for path in bundles:
    with path.open('rb') as f:
        info = plistlib.load(f)
    assert info['CFBundleVersion'] == '42', f'Build number override missing: {path}'
    assert info['CFBundleShortVersionString'] == '1.2.3', f'Marketing version override missing: {path}'
print('Verified version overrides in all three archived bundles')
PY

