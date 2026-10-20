# TestFlight setup

## Apple resources

Use the existing Apple Developer Program membership. Register these explicit identifiers (or consistently override the base identifier):

| Target | Default bundle ID |
| --- | --- |
| iPhone | `com.agawlbb.alarmbeans` |
| Watch | `com.agawlbb.alarmbeans.watchkitapp` |
| Complication | `com.agawlbb.alarmbeans.watchkitapp.complication` |

Register `group.com.agawlbb.alarmbeans` and enable that App Group on all three identifiers. The group is device-local: it shares Watch state with the complication; it does not sync storage across devices. WatchConnectivity performs device synchronization.

Create an iOS App Store Connect app record for the phone identifier, including its embedded Watch app. Create an Apple Distribution certificate with its private key and App Store distribution provisioning profiles for all three targets. Confirm the Watch smart-alarm background mode is appropriate for this fixed-time wake-up application before an external beta submission. Do not add unrelated workout/audio modes to obtain runtime.

## GitHub configuration

Create the `testflight` GitHub environment. Restrict deployment to `main` if desired. Add these environment secrets using GitHub's UI; never paste private keys or certificate contents into an issue or commit:

| Secret | Value |
| --- | --- |
| `APPLE_TEAM_ID` | Apple Developer team identifier |
| `DISTRIBUTION_P12_BASE64` | Base64-encoded Apple Distribution certificate and private key exported as `.p12` |
| `DISTRIBUTION_P12_PASSWORD` | Password protecting that `.p12` |
| `PHONE_PROFILE_BASE64` | Base64-encoded iPhone App Store provisioning profile |
| `WATCH_PROFILE_BASE64` | Base64-encoded Watch App Store provisioning profile |
| `COMPLICATION_PROFILE_BASE64` | Base64-encoded complication App Store provisioning profile |
| `ASC_KEY_ID` | App Store Connect API key ID |
| `ASC_ISSUER_ID` | API key issuer ID |
| `ASC_PRIVATE_KEY_BASE64` | Base64-encoded API `.p8` private key |

The App Store Connect API key must have access sufficient to upload builds to this app. If using different registered identifiers, set GitHub environment variables `ALARM_BEANS_BUNDLE_ID` and `ALARM_BEANS_APP_GROUP` to match them. The generated provisioning-profile names are extracted from the provided profiles.

On macOS, encode a file without line breaks:

```sh
base64 -i your-file | tr -d '\n' | pbcopy
```

Paste into the corresponding GitHub secret field. This command copies the encoded credential to your clipboard; clear it afterward.

## Upload and internal testing

1. Confirm the **Build and test** workflow passes for the intended `main` commit.
2. Run **Upload internal TestFlight build** on `main`. It runs the tests again, signs all embedded targets, and uploads the IPA. Signing material is removed by the script's exit trap; the Mac runner is ephemeral.
3. Wait for App Store Connect processing and resolve any signing, metadata, or export-compliance messages.
4. Create an internal TestFlight group, select the processed build, and add your App Store Connect testers. Uploading alone does not create a tester group or invite people.
5. Install the phone and Watch companion through TestFlight and follow the device-validation checklist.

The release workflow's run number supplies the build number. A rerun uses the same number; after an accepted upload, start a new workflow run for another upload. The marketing version is `0.1.0` in `Config/Base.xcconfig`.

The initial manual upload workflow also enables prototype distribution for physical-device testing. An upload is not evidence that the alarm behavior has passed device validation.

Before external testing, complete the physical tests, supply beta description, feedback/contact details and review notes explaining the paired alarm behavior, and submit for Apple's beta review. Configure the external group only after that step; the workflow does not automatically invite external testers.

References: [upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds), [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/).
