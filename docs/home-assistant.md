# Home Assistant

Alarm Beans exposes exactly four entities per paired installation:

| Entity | Direction | Meaning |
| --- | --- | --- |
| Wake time (`time`) | Read/write | Saved local hour and minute, without seconds or a date |
| Alarm enabled (`binary_sensor`) | Read only | Last reported confirmation that both device alarms are armed or alerting |
| Haptic interval (`number`) | Read/write | 1–60 seconds between Watch haptics |
| iPhone offset (`number`) | Read/write | 1–30 minutes after the Watch wake time |

No arm switch, additional sensors, diagnostic entities, or public events are created. HA cannot arm or reschedule an alarm. Arm remains a Watch action.

## Install and pair

1. Copy `HomeAssistant/custom_components/alarm_beans` into your HA configuration's `custom_components/alarm_beans` directory. This custom integration targets Home Assistant 2026.10 or later; it uses the HA-supported `segno==1.6.6` dependency to render QR codes. Restart HA after installation.
2. In **Settings → Devices & services → Add integration**, select **Alarm Beans**. Supply your HA HTTPS origin, for example `https://your-instance.ui.nabu.casa`. It must be reachable by the iPhone with a normally trusted certificate; HTTP, certificate bypasses, URL user/passwords, and path/query/fragment URLs are unsupported.
3. HA displays a QR code. On iPhone, open **Alarm Beans → Settings → Home Assistant → Scan pairing code**. Confirm the displayed server hostname. Scanning automatically completes HA's setup flow. No separate Watch pairing is needed.
4. Open both apps while the Watch and phone can communicate. HA values are initially unknown until the phone reports them. Choose presets through the three writable entities, then open the phone or Watch to synchronize. Always arm the values displayed on the Watch.

QR codes expire after five minutes and work once. Submit the HA pairing form again to refresh an expired code. Pairing sessions do not survive an HA restart. Use the integration's options to **Pair iPhone again** or **Revoke iPhone access**; re-pairing replaces the previous credential. The phone's **Disconnect** action also revokes access before removing its Keychain record. An unavailable server cannot confirm revocation; use HA options if the phone cannot connect.

## Pending, accepted, and rejected changes

Entity states show the last values reported by the phone, rather than treating requested values as accepted. Attributes on the same entities expose `last_sync` and `settings_locked`. Writable entities additionally expose `request_status`, `pending_value` while pending/claimed, and `rejection_reason` when rejected. There are no extra status entities. The binary sensor is the last reported state, not a continuous live connection; inspect `last_sync` when interpreting it.

HA retains the latest undelivered request per field. Opening iPhone fetches pending work and reports accepted settings and enabled state. Opening Watch asks the reachable phone to run that bridge; WatchConnectivity may wake the phone, but delivery and network access are best effort. There is no APNs dependency, background polling, or persistent connection. If no connection can be made, displayed settings and scheduled alarms remain in force. An offline Watch can arm its existing displayed settings; it does not wait indefinitely for HA presets.

The phone acknowledges an edit only after the Watch accepts it. A request that meets a locked alarm or unavailable Watch is rejected, reported, and discarded. Make a new HA request after opening both apps if needed. Requests that were delivered but never acknowledged are discarded on the next exchange, including after HA restarts; uncertain deliveries are never replayed after dismissal. A receipt journal in Keychain is written before applying each request and retained until HA acknowledges it. An acknowledgement exchange never claims new work; newly arrived requests wait for the next synchronization.

## Arming invariant

The coordinator accepts edits only when it is safe to create a new alarm: no busy arm, blocking occurrence, scheduled device component, pending cancellation, or storage failure. Every local and received settings path uses that lock. Arm atomically captures the displayed preferences, enters preparing, rotates the persisted Watch-issued settings epoch, and schedules both devices from that immutable occurrence. The phone stores the captured settings carried in the prepare message; it never constructs its fallback from mutable preferences.

An edit racing with Arm either reaches the Watch before capture and becomes the displayed/scheduled value, or is rejected. During preparing/armed/alerting, both main screens use the occurrence wake time. Delayed pre-arm settings messages carry an old epoch and remain rejected even after dismissal. No HA command changes an existing occurrence. Cancellation, tombstones, backward-compatible settings decoding, and runtime recovery remain in the existing coordinator.

## Security and storage

The QR carries only an HTTPS origin and a short-lived, single-use pairing token. Its image is served through a separate unguessable, expiring handle with no-store caching; tokens are not embedded in image URLs. HA stores only a SHA-256 hash of the revocable device credential in the config entry. The iPhone stores the credential and receipt journal in a non-migrating, device-only Keychain item accessible after first unlock so a Watch connectivity wake can synchronize. The Watch never receives the HA credential. HA administrator or long-lived access tokens are not used by the phone.

API bodies and credentials are never logged. The client rejects redirects, uses normal HTTPS certificate validation and ephemeral URL sessions, and limits request time and response size. These endpoints authorize only this integration's reports, pending settings, pairing, and revocation; they cannot invoke other HA services. HA checks revocation again inside the state lock before accepting a report. The integration uses HA's Store and config-entry APIs, not direct edits to `.storage` files.

## Validation

Local protocol tests: `python -m unittest discover -s HomeAssistant/tests -v`. The six framework-contract tests require HA and are skipped locally if absent. Linux CI pins `homeassistant==2026.10.0` on Python 3.14 and runs the entity/HTTP/config-flow contracts against actual HA classes. Apple CI uses the repository's pinned tooling and runs the Swift race, lock, stale-message, offline, migration, and bridge tests before all three target builds and archive validation.

Physical checks still required: trusted HTTPS access from your network and remote connection; QR rendering and camera permission on a real iPhone; completion/expiry/reuse/revocation through HA's frontend; Keychain availability during a locked-phone WatchConnectivity wake; both-device app-open synchronization; actual face/display transitions while racing HA edits with Arm; offline arming; cancellation and overnight alarm behavior. Automated tests do not establish alarm reliability or background delivery timing. This implementation does not install the integration on your server or authorize a TestFlight release.
