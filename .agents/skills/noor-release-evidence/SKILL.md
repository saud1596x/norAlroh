---
name: noor-release-evidence
description: Bind Noor release claims to exact source, native execution, archived resources, migration and actual Apple delivery state.
---

Read `docs/release-acceptance.json` and the current diff. Preserve uncommitted work; record resume state in that ledger rather than creating another report tree.

1. Match commit, configuration, Xcode/SDK, resource/model versions and the built product. A shared native product must pass immutable producer/source/archive/hash binding before and after consumer tests.
2. Inspect original command exits, xcresult tree/counts, missing/skipped cases, original screenshots and continuous video. Helper fixtures/grammar are not native execution; quiet input is not ASR accuracy; geometry is not design approval.
3. Run affected checks once and read full results. Repeat only for a changed source, failure or unresolved concern. Do not extend acceptance deadlines, synthesize receipts or accept another lane's image in place of missing evidence.
4. Inspect the actual signed IPA, all extensions, Quran/fonts/model/audio/privacy files and entitlements. Confirm supported upgrade/migration with test data before declaring a candidate.
5. All blocking QUR/REC/WGT/NTF/UX/DATA/REL items need suitable evidence. Public App Store delivery is authorized by the current owner only after those gates, not by a successful upload alone.
6. Keep upload, Apple processing, TestFlight availability, review submission, approval and public publication as distinct observed states. Prepare concrete missing owner actions only after independent work is complete.

**Examples:** valid source-bound fixture input to the evidence validator proves validator behavior only. `test_old_source_cannot_reuse_current_screenshots`, missing producer binding and `test_each_missing_extension_is_rejected` must reject altered fixtures. Use the existing Python test commands in `scripts/tests/`; do not mutate a user's IPA or evidence.

**History:** 2026-10-31: integrates the false-green, stale live log, COLR and55-minute combined-job lessons. No existing historical review JSON becomes approval for a new source.
