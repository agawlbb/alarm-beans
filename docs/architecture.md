# Alarm coordination

The Watch is the sole creator of alarm occurrences because watchOS requires its app to be active when scheduling a smart-alarm runtime session. Either app can edit remembered settings or stop the current occurrence. Settings synchronize by timestamp and deterministic UUID tie-break; editing settings never changes a scheduled occurrence.

## Arming

1. Watch persists a new UUID and `preparing` record.
2. Phone validates the occurrence and persisted cancellation tombstones, persists intent, then schedules AlarmKit at `wakeTime + offset`.
3. After the phone acknowledgment, Watch schedules the extended runtime session at the wake time.
4. Watch asks phone to confirm the pair, then persists `armed` after the reply. A complication time requires both scheduling flags and an armed/alerting phase.

Any error attempts cancellation of both sides. Lost acknowledgments are treated as uncertain scheduling, not success. A disconnected cancellation is persisted and retried. Interrupted preparing records are cleaned up on launch; the phone also cleans up abandoned preparations older than two minutes when reconciling.

## Cancellation and recovery

A cancellation tombstone is saved before touching the scheduler or communicating. Repeated cancels are idempotent. Tombstones are retained even after confirmation so delayed preparation/confirmation/state messages cannot resurrect an occurrence. Messages are scoped to occurrence UUIDs, so an old cancellation does not dismiss a newer pair.

WatchConnectivity immediate messages supply acknowledgments. Durable user-info transfers carry cancellations and acknowledgments; application context coalesces settings changes. Reconnection and foreground launch retry pending cancellation and query the counterpart. No network service is required.

AlarmKit owns the audible phone alarm even when its app is suspended. The Watch session owns repeating haptics. A Watch runtime failure leaves the phone fallback in place. The Watch system Stop event and iPhone Stop App Intent route into the same coordinator.

The phone enumerates AlarmKit alarms during reconciliation. WatchKit offers no equivalent scheduled-session enumeration. A relaunched Watch process assigns its delegate as soon as watchOS supplies the scheduled runtime session and consults durable state before playing haptics. A cold-process cancellation suppresses future haptics even if the original session object is unavailable. Scheduled-session invalidation may require the Watch app to be active; until it succeeds, cancellation remains pending. These limitations are explicit physical-test cases, including any native warning from a suppressed session.

## Storage and rendering

An atomic JSON snapshot in a device-local App Group container stores settings, occurrence state, pending cancellations, and tombstones. The file is available after first unlock. Missing storage entitlements or corrupt state prevent arming; the app does not silently replace unreadable state and claim success.

The complication reads that same Watch file. Its timeline includes wake and runtime-expiry transitions; updates request a WidgetKit reload. There is no per-minute widget polling. Tapping uses `alarmbeans://alarm` to reset navigation to the alarm screen.

App countdowns derive from absolute scheduled dates using a SwiftUI minute timeline and refresh when views become active. Positive durations round up to the next minute. Draft previews recalculate the next local occurrence; armed alarms retain their original instant across timezone changes.
