#!/bin/bash
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="/Applications/Xcode_$(tr -d '\r\n' < .xcode-version).app/Contents/Developer"
mkdir -p build/Previews
xcrun simctl list devices available --json > build/Previews/devices.json
read -r phone watch < <(python3 - <<'PY'
import json
with open('build/Previews/devices.json') as f:
    runtimes = json.load(f)['devices']
phones = [d['udid'] for r, ds in runtimes.items() if 'iOS' in r for d in ds if d['name'].startswith('iPhone')]
watches = [d['udid'] for r, ds in runtimes.items() if 'watchOS' in r for d in ds if 'Apple Watch' in d['name']]
assert phones and watches, 'iPhone and Watch simulators required for previews'
print(phones[0], watches[0])
PY
)
xcrun simctl pair "$watch" "$phone"
for device in "$phone" "$watch"; do
  xcrun simctl boot "$device"
  xcrun simctl bootstatus "$device" -b
done
xcrun simctl install "$phone" build/DerivedData/Build/Products/Debug-iphonesimulator/AlarmBeans.app
xcrun simctl install "$watch" build/WatchDerivedData/Build/Products/Debug-watchsimulator/AlarmBeansWatch.app
xcrun simctl launch "$phone" com.agawlbb.alarmbeans
xcrun simctl launch "$watch" com.agawlbb.alarmbeans.watchkitapp
# Allow the first SwiftUI frame and connectivity activation to settle.
sleep 5
xcrun simctl io "$phone" screenshot build/Previews/iPhone.png
xcrun simctl io "$watch" screenshot build/Previews/Watch.png
xcrun simctl shutdown "$watch"
xcrun simctl shutdown "$phone"
