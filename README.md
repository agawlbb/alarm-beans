# Alarm Beans

[![Build and test](https://github.com/agawlbb/alarm-beans/actions/workflows/ci.yml/badge.svg)](https://github.com/agawlbb/alarm-beans/actions/workflows/ci.yml)

A quieter morning: repeating Apple Watch haptics at your wake time, followed by a native iPhone audible fallback if you still need it. One tap on the Watch arms both alarms.

**Early beta implementation.** Overnight reliability and Apple's intended-use fit for the smart-alarm background mode require physical-device validation. Simulator and CI builds cannot establish wake-up reliability. See [device validation](docs/device-validation.md).

## Use

1. Install the iPhone app and its Watch companion on iOS 26 / watchOS 26 or later.
2. Open **Setup & alarm permission** on iPhone and allow alarms.
3. Choose a wake time on either device. Timing settings default to a five-minute fallback and Watch haptics every five seconds.
4. On the Watch, tap **Arm both alarms** and keep the app open until **Armed** appears.
5. Tap **Stop both alarms** on either device to dismiss. If cancellation is pending, the other device may still alert; open both apps to confirm.

Both apps show the scheduled date/time and hours and minutes remaining. Settings are remembered; one upcoming wake-up is supported, without recurrence or snooze.

Add **Alarm Beans** through the Watch face complication editor. Circular, rectangular, inline, and corner layouts show the wake time only for a confirmed active pair. An inactive alarm shows no time; an attention icon means open the app. Tapping always opens the alarm screen. watchOS controls the timing of complication refreshes.

## Build

All Apple builds run on GitHub-hosted Mac runners. Xcode **26.6** and XcodeGen **2.44.1** are pinned in `.xcode-version` and `.xcodegen-version`.

On a Mac with that Xcode installed:

```sh
bash scripts/ci.sh
```

This generates `AlarmBeans.xcodeproj`, runs the shared Swift package tests, and builds the iPhone, Watch, and complication targets for simulators. The generated project and build products are intentionally ignored by Git.

For development signing, create an ignored `Config/Local.xcconfig`:

```xcconfig
DEVELOPMENT_TEAM = YOUR_TEAM_ID
// Override these only if the default identifiers are unavailable:
// ALARM_BEANS_BUNDLE_ID = com.yourcompany.alarmbeans
// ALARM_BEANS_APP_GROUP = group.com.yourcompany.alarmbeans
```

Run `bash scripts/bootstrap.sh`, open the generated project in Xcode, and select the paired physical devices. The registered App Group must be enabled for the phone, Watch, and complication identifiers.

## TestFlight

The manual **Upload internal TestFlight build** workflow builds, tests, signs, and uploads the paired app from `main`. It requires your Apple signing assets and App Store Connect configuration. Follow [TestFlight setup](docs/testflight.md). No credentials are stored in this repository.

## Structure

- `Packages/AlarmCore`: scheduling, countdown formatting, durable state, messages, coordination, and fault-injection tests.
- `Apps`: shared SwiftUI screens and connectivity/storage adapters; platform alarm adapters; Watch complication.
- `project.yml`, `scripts`, `.github/workflows`: reproducible project generation, Mac builds, signing, and upload.

The iPhone fallback uses AlarmKit, not an ordinary notification. The Watch uses a schedulable extended runtime session. Each device schedules its own alarm locally; cancellation uses WatchConnectivity and cannot be immediate across an unavailable connection. Watch runtime failures preserve the audible phone fallback.

## License

Source is licensed under the [Mozilla Public License 2.0](LICENSE). Modifications to covered source files distributed to others must remain available under MPL-2.0. See source notices and the in-app source link. The app uses no third-party runtime packages.
