# Alarm Beans

[![Build and test](https://github.com/agawlbb/alarm-beans/actions/workflows/ci.yml/badge.svg)](https://github.com/agawlbb/alarm-beans/actions/workflows/ci.yml)

A quieter morning: repeating Apple Watch haptics at your wake time, followed by a native iPhone audible fallback if you still need it. One tap on the Watch arms both alarms.

**Early beta implementation.** Overnight reliability and Apple's intended-use fit for the smart-alarm background mode require physical-device validation. Simulator and CI builds cannot establish wake-up reliability. See [device validation](docs/device-validation.md).

## Use

1. Install the iPhone app and its Watch companion on iOS 26 / watchOS 26 or later.
2. Open the iPhone app and allow its automatic alarm permission prompt. If access was previously denied, use **Open Settings** in the app's settings to enable it.
3. Choose a wake time on either device. Timing settings default to a five-minute fallback and Watch haptics every five seconds.
4. On the Watch, tap the hour or minute digits and turn the Digital Crown to edit. Each field wraps independently in either direction. In 12-hour mode, tap AM/PM to change period. Tap **Arm** and keep the app open until **Active** appears.
5. Tap **Stop** on either device to dismiss. If cancellation is pending, the other device may still alert; open both apps to confirm.

Both apps show the Watch alarm time and activity status. The Watch shows time remaining only for an active alarm. Tap the inactive time on iPhone to edit it. The Watch gear appears only when inactive and contains haptic pattern, haptic interval, and phone offset; selecting a pattern previews it on the Watch. The iPhone gear also contains permissions, About, and cancellation status. After stopping on iPhone, its main screen shows Inactive while durable Watch cancellation retries continue. Stop an active alarm before changing its time or timing settings. Settings are remembered; one upcoming wake-up is supported, without recurrence or snooze.

Crown input has one owner for the entire time editor. Switching fields resets accumulated rotation and invalidates queued callbacks from the previous selection. Hours require two input units per step and minutes one, both at the system's low sensitivity; feedback plays only when a displayed number changes. Alarm start does not request display illumination. The ringing screen has a larger Stop control.

The Watch has dedicated layouts: a gear beside Inactive, a full-width Arm row, compact settings rows, and separate pattern/interval/offset lists. Pattern buttons preview and check a choice without navigating back. The phone's form is not used on the Watch.

Add **Alarm Beans** through the Watch face complication editor. Circular, rectangular, inline, and corner layouts show the wake time only for a confirmed active pair. Small active layouts show only the time; the rectangular layout adds Alarm armed. Inactive layouts show an alarm icon or No alarm; an attention indicator means open the app. Tapping always opens the alarm screen. watchOS controls the timing of complication refreshes.

## Build

All Apple builds run on GitHub-hosted Mac runners. Xcode **26.6** and XcodeGen **2.44.1** are pinned in `.xcode-version` and `.xcodegen-version`.

On a Mac with that Xcode installed:

```sh
bash scripts/ci.sh
```

This generates `AlarmBeans.xcodeproj`, runs the shared Swift package tests, builds the iPhone, Watch, and complication targets for simulators, and creates an unsigned device archive to check release packaging. The generated project and build products are intentionally ignored by Git.

For development signing, create an ignored `Config/Local.xcconfig`:

```xcconfig
DEVELOPMENT_TEAM = YOUR_TEAM_ID
// Override these only if the default identifiers are unavailable:
// ALARM_BEANS_BUNDLE_ID = com.yourcompany.alarmbeans
// ALARM_BEANS_APP_GROUP = group.com.yourcompany.alarmbeans
```

Run `bash scripts/bootstrap.sh`, open the generated project in Xcode, and select the paired physical devices. The registered App Group must be enabled for the phone, Watch, and complication identifiers.

## TestFlight

Every normal push to `main` runs validation and **Prepare signed build**, which builds, tests, signs, and exports the paired app. The workflow can also be run manually. TestFlight upload is disabled by default; its explicit **publish** input must be enabled to upload and automatically distribute to the existing internal group. With publish off, the signed IPA and symbols remain GitHub artifacts. Signing requires your Apple signing assets; upload additionally requires App Store Connect configuration. Follow [TestFlight setup](docs/testflight.md). No credentials are stored in this repository.

## Home Assistant

The optional [Home Assistant integration](docs/home-assistant.md) provides a wake-time entity, read-only paired-alarm binary sensor, haptic-interval number, and iPhone-offset number. Pair by scanning HA's single-use QR code in the iPhone settings. HA presets synchronize on app opening; arming remains on Watch, and settings are locked throughout preparing and active alarms.

## Structure

- `Packages/AlarmCore`: scheduling, countdown formatting, durable state, messages, coordination, and fault-injection tests.
- `Apps`: shared SwiftUI screens and connectivity/storage adapters; platform alarm adapters; Watch complication.
- `project.yml`, `scripts`, `.github/workflows`: reproducible project generation, Mac builds, signing, and upload.

The iPhone fallback uses AlarmKit, not an ordinary notification. The Watch uses a schedulable extended runtime session. Each device schedules its own alarm locally; cancellation uses WatchConnectivity and cannot be immediate across an unavailable connection. Watch runtime failures preserve the audible phone fallback.

## License

Source is licensed under the [Mozilla Public License 2.0](LICENSE). Modifications to covered source files distributed to others must remain available under MPL-2.0. See source notices and the in-app source link. The app uses no third-party runtime packages.
