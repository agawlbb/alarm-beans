# Physical-device acceptance

## Minimal interface and phone permission checks

- On a 40mm Watch, confirm the settings gear sits beside Inactive and Arm fills its own bottom row without scrolling. Confirm the approved settings screens still work unchanged.
- Check rectangular widgets: No alarm while inactive; alarm time and Alarm armed while active. Check small widgets: an alarm icon while inactive, only the alarm time while active. Tapping still opens the alarm app. Error states must continue to direct you to check the app.
- On a fresh iPhone install, open the app and allow the automatic alarm permission prompt. Relaunch and return from background: no repeat prompt or permission row should appear once allowed.
- Deny permission, then confirm Settings offers Open Settings. Enable alarms in iOS Settings and return: the row should disappear. Arming must still reject missing permission.

Status: **partial user testing; paired dismissal failed**. Record results, device models, OS versions, build number, and dates here. Do not infer device reliability from simulator builds or shared-package tests.

## Reported results — October 21, 2026

During the build 1.0 (3) test session, the user reported successful arming and Watch haptic playback. The user then reported that swiping to dismiss the iPhone Lock Screen alarm stopped the phone alarm but left the Watch alerting. Exact device models, OS versions, and timing measurements were not supplied. Overnight operation remains unverified.

This fails the requirement that dismissal on either device immediately stops both. The Watch adapter rejects session invalidation while its app is inactive, following [Apple's documented restriction](https://developer.apple.com/documentation/watchkit/wkextendedruntimesession/invalidate%28%29). A delivered cancellation is persisted and retried when the Watch app becomes active. This restriction alone can explain continued Watch haptics; the report does not establish whether the phone's stop intent ran or the cancellation message arrived. Retest those paths separately before attributing the entire failure to message delivery or the Lock Screen gesture.

For the current build, stop through the Watch system alert or open Alarm Beans on the Watch to complete cancellation. Verify that opening the Watch app after phone dismissal stops its session and clears the pending state. Immediate remote dismissal of a background Watch alert remains an unresolved platform/design requirement.

## Feasibility gate

- [ ] Confirm with Apple's documented intended use, and Apple Developer Support if necessary, that a fixed-time silent wake-up qualifies for the smart-alarm extended runtime mode. The documentation describes heart-rate/motion-based smart alarms; this app does not collect health data or implement sleep-stage detection.
- [ ] Arm from an active Watch app; confirm both schedulers acknowledge before **Armed** appears.
- [ ] Verify arming does not invoke the unsupported auto-launch authorization API or fail with its error 10. Verify a pending scheduling request does not immediately fail. Record any watchOS error domain/code shown after a genuine scheduling rejection, and confirm the phone preparation is canceled on failure.
- [ ] Close the app normally, lower the wrist, leave both apps suspended overnight, and verify haptics begin at the selected time without sound.
- [ ] Verify five-second repeats continue with the screen off, until dismissal or the platform runtime limit.
- [ ] Leave the Watch alarm undismissed and confirm the iPhone itself sounds at the five-minute fallback, including while the Watch is paired and worn. Record AlarmKit's paired-Watch presentation behavior.
- [ ] Dismiss through the Watch system alert's Stop button; verify it cancels the phone fallback before its scheduled time.

If a core requirement fails, retain the native phone fallback and report the exact platform limitation before treating this as a release-ready alarm. Do not substitute local notifications or unrelated background modes.

## Failure and lifecycle cases

- [ ] Stop from the foreground app on either device; both devices confirm dismissal.
- [ ] Stop the iPhone AlarmKit system alert; Watch haptics stop or show a truthful pending state until the Watch app can invalidate its session.
- [ ] Disconnect, dismiss on Watch, and verify local haptics stop while the phone fallback remains. Reconnect and verify cancellation is retried and confirmed.
- [ ] Dismiss during each arming stage, lose the scheduling acknowledgment, and retry. No old alarm may reappear.
- [ ] Restart each device separately before the alarm. Record differences between ordinary suspension, process termination, force quit, device restart, and first unlock.
- [ ] Cold-launch the Watch app after its process was terminated, dismiss the saved alarm, and verify a subsequently delivered system session never plays haptics. Check whether the old scheduled session prevents immediate rearming; watchOS does not expose a list of scheduled extended sessions.
- [ ] Revoke AlarmKit permission, remove the Watch companion, or disable Watch haptics/auto-launch. Verify the user sees the problem and is not given a false successful arm confirmation where detectable.
- [ ] Exercise Watch runtime expiration and suppression; preserve the phone fallback and show action needed.
- [ ] Test Sleep Focus, Silent Mode, Always On, low power, locked devices, and a charging/unworn Watch.
- [ ] Test a wake-up less than one minute away, a fallback across midnight, daylight-saving transitions, and timezone/manual clock changes after arming.

## Complication and countdown

- [ ] Verify circular, rectangular, inline, and corner layouts on supported faces and Watch sizes. No active time is clipped; 12/24-hour formatting follows the system.
- [ ] Verify drafts, arming, failed pairs, dismissal, and pending cancellation have **no time**. Pending cancellation shows attention. Confirmed armed/alerting pairs show the Watch wake time.
- [ ] Observe watchOS refresh latency after stopping on either device. The app requests reloads, but watchOS controls when they render.
- [ ] Tap the complication while inactive, armed, alerting, and while the app is in settings. Each tap reaches the main alarm screen with setting/view/dismiss controls.
- [ ] Verify time disappears after the Watch session's maximum lifetime, even without a fresh application launch.
- [ ] Verify both main screens show only the Watch alarm time, activity status, and hours and minutes remaining. No backup time, calendar date, or introductory copy appears. Countdown updates at minute boundaries, refreshes on resume, and never goes negative.
- [ ] On Watch, tap hour/minute to focus it and turn the Crown. Verify forward/backward wrapping (12 to 1, 59 to 00; 23 to 00 in 24-hour mode), independent fields, AM/PM selection, and VoiceOver adjustment. Active alarms cannot be edited.
- [ ] Switch hours to minutes and back repeatedly, including during a Crown turn. The first movement edits only the selected field; leftover partial turns must not transfer. Verify the slower hour/minute stepping on hardware and haptic feedback only for actual value changes.
- [ ] On Watch, verify no inactive countdown, and a settings gear only when inactive. Settings contains only Haptic pattern, Haptic interval, Phone offset, and Done. Verify pattern selection previews a haptic, persists after relaunch, synchronizes to phone, and is used by the next scheduled alarm. Upgrade from build 5 with saved settings and an active occurrence; absent pattern fields default to Notification.
- [ ] Verify the gear beside Inactive and the full-width Arm row are visible without scrolling on the smallest Watch. Settings rows show full names and values without letter-by-letter wrapping. Selecting multiple patterns must leave the Pattern list open, with only Back returning. Interval/offset use separate numeric lists. Capture home, settings, pattern before/after observable updates, interval, offset, and active/inactive widget content using `scripts/watch-review.sh`; these Debug-only fixtures are excluded from release builds.
- [ ] Stop on iPhone while the Watch app is inactive. Its main screen shows Inactive without pending text or retry controls, but Settings retains cancellation status. Opening the Watch must still complete the durable pending cancellation.
- [ ] While ringing, open the Watch app and verify the larger Stop button is visible. Confirm Alarm Beans makes no attempt to illuminate the display or change Sleep Focus.
- [ ] On iPhone, tap the inactive time to edit. Verify the gear button opens timing, About, cancellation status when applicable, and Open Settings only when alarm access is denied; it remains available while active with timing changes disabled. Verify the automatic first-launch permission flow and authorized/denied resume cases listed above.
- [ ] Verify VoiceOver, larger text, dimmed/Always On rendering, and sufficient contrast.

## Overnight trial log

| Build | Devices / OS | Date | Silent Watch start | Audible phone fallback | Paired Stop | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| Pending | | | | | | |
