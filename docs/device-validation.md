# Physical-device acceptance

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
- [ ] On iPhone, tap the inactive time to edit. Verify the gear button opens timing, permissions, setup, and About, and remains available while active with timing changes disabled.
- [ ] Verify VoiceOver, larger text, dimmed/Always On rendering, and sufficient contrast.

## Overnight trial log

| Build | Devices / OS | Date | Silent Watch start | Audible phone fallback | Paired Stop | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| Pending | | | | | | |
