# Publication checkpoint — 2026-10-09

Latest user instruction at 03:46 Asia/Riyadh: check all requirements, complete failures and publish; do not send images or video. This supersedes the former final screenshot/video delivery and user visual-review pause. It does not authorize claiming untested behavior or accepting third-party contracts without required action-time confirmation.

## Current verified scope and remaining work

| Requirement | Evidence and current limit |
| --- | --- |
| Original Quran page drawing and tools | Prior native viewport/halo/reader gates passed both phone sizes. Current final combined Release regression has not run. No replacement fonts, text reflow or generated images were introduced. |
| Immediate first-use offline original Mushaf | Not complete. Original QCF V2 fonts and row metadata are bundled, but exact Content Sync glyph data still require the first fetch. The current service prohibits build-time bundled snapshots; no independent exact-data redistribution grant is verified. Cached-first opening is already implemented in the interactive reader; the legacy reader still awaits refresh first. |
| Tajweed | Hidden where exact trusted glyph/rule mapping is not available. No unverified rule colors or pronunciation certification. |
| Inline Hifz and local audio | Earlier native self-session/capture/repeat gates passed. Optional word-recognition source is also present; it does not certify Tajweed. Separate practice help now records only from the real playback-start callback for the current verse; its new native gate is pending. Daily goals and spaced review exist. |
| Khatmah-linked visible protection | Complete code batch 67a8e13 passed native run 37865932405 on both phone sizes. Compact job 113612540831 succeeded in 13m 5s with 27 selected native units and five actual UI tests, zero failures; large job 113612540560 also succeeded, with full run duration 17m 48s. Physical Family Controls authorization/shielding remains unverified. |
| Account and settings | Apple-only optional account source and Firebase provider setup exist. Production sign-in, two-device synchronization and account deletion need actual acceptance; source/emulator checks cannot prove these. |
| Widgets and counters | Native widget/counter/khatmah gate 37862067424 passed both sizes on 10bd73c. Physical widget gallery/update behavior unverified. |
| Independent reminders | Prayer, khatmah and legacy fixed-window salawat reminders exist. Independent dua/morning/evening/salawat/Hifz editors, frequency, weekdays, quiet hours, bounded seven-day reconciliation, raw export/erasure and accurate deep links are now implemented locally; native acceptance is pending. |
| Final signing and store | All five required Codemagic profile reference names and matching certificate were observed read-only. Their entitlements and a current-source signed archive have not been verified. The TestFlight preview source gate currently rejects the changed InteractiveMushafCanvas.swift hash; no stale preview approval was repinned or bypassed. |

## Local integrity checks

2026-10-09: 17 scripts/tests tests passed. Exact source-copy verifier checked all 6,236 Quran verses and 112 separate basmalas without normalization or mismatches. These tests do not certify glyph semantics, hardware or specialist religious review.

## Publication status

NOT PUBLISHED. No current-source TestFlight upload, App Store submission, review acceptance or public release is claimed. Existing old build and approval records are historical and cannot satisfy current-source checks. Final native tests, remaining source work, resource rights and actual service/device acceptance remain. The browser policy blocking native app-artifact downloads remains respected; no alternate transport was used.
