#!/bin/bash
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="/Applications/Xcode_$(tr -d '\r\n' < .xcode-version).app/Contents/Developer"
mkdir -p build/WatchReview
xcrun simctl list devices available --json > build/WatchReview/devices.json
watch="$(python3 - <<'PY'
import json, re
with open('build/WatchReview/devices.json') as f:
    runtimes = json.load(f)['devices']
candidates = []
for runtime, devices in runtimes.items():
    if 'watchOS-26' not in runtime:
        continue
    for device in devices:
        match = re.search(r'(\d+)mm', device['name'])
        if match:
            candidates.append((int(match[1]), device['name'], device['udid']))
assert candidates, 'No watchOS 26 simulator available'
size, name, udid = min(candidates)
print(udid)
with open('build/WatchReview/device.txt', 'w') as f:
    f.write(f'{name}\n{udid}\n')
PY
)"
trap 'xcrun simctl shutdown "$watch" >/dev/null 2>&1 || true' EXIT
xcrun simctl boot "$watch"
xcrun simctl bootstatus "$watch" -b
xcrun simctl install "$watch" build/WatchDerivedData/Build/Products/Debug-watchsimulator/AlarmBeansWatch.app
for screen in home settings pattern pattern-changing interval offset widget-large-unarmed widget-large-armed widget-small-unarmed widget-small-armed; do
  xcrun simctl terminate "$watch" com.agawlbb.alarmbeans.watchkitapp >/dev/null 2>&1 || true
  xcrun simctl launch "$watch" com.agawlbb.alarmbeans.watchkitapp --interface-review "$screen"
  sleep 4
  xcrun simctl io "$watch" screenshot "build/WatchReview/$screen.png"
done
cat build/WatchReview/device.txt
