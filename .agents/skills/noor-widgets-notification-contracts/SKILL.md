---
name: noor-widgets-notification-contracts
description: Implement and verify Noor WidgetKit timelines, App Group snapshots, deep links and fixed prayer/reminder policy without conflating system permissions.
---

Read WGT and NTF items and the current owner policy before changing existing targets or scheduled identifiers.

- Preserve current widget kind IDs and the embedded extension. Local dua selection and 48-hour timelines do not need notifications, a network, an account or ML resources.
- Use entry.date and immutable duaID, calendar/timezone-aware future hour boundaries and family-appropriate complete text. Validate corpus provenance and DST gaps/repeated hours. A tapped old entry must open its own duaID after the hour changes.
- Persist a small versioned App Group snapshot atomically. Do not credit reading on widget navigation or load recitation/audio databases in the extension.
- Inspect actual archived targets, entitlements, provisioning and gallery installation separately from Swift source. Preview images do not prove Home/Lock Screen installation or hourly delivery.
- AlarmKit and UserNotifications authorizations are independent. On supported iOS, prayer alarms use fixed dated events and a working stop action; the salawat reminder is one silent repeating300-second notification. Do not secretly add frequency controls, quiet hours or per-prayer switches.
- Reconcile only known IDs against actual system requests; retain stopped alarm identities, tolerate partial failure and report coverage. Never clear all unrelated requests or reset a valid repeat on every launch.

**Examples:** run the actual `WidgetTimelineTests` for current/local-boundary/DST and stable-link behavior. Stale/corrupt snapshot fixtures must produce a safe truthful empty state, not progress or a crash. Notification permission/device cases and real hourly updates remain separate tests and cannot be inferred from these fixtures.

**History:** 2026-10-31: new owner fixed-policy and hourly-dua requirements supersede older configurable reminders. Keep implementation/API evidence tied to the exact SDK, source and central ledger.
