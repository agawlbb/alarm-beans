#!/bin/bash
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail
cd "$(dirname "$0")/.."
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

