# Noor Alruh implementation and acceptance

Latest instruction: 2026-10-08 Asia/Riyadh. Keep interim reports, files, screenshots internal. Stop before publishing for user review. A successful build alone is never acceptance.

## Safeguards
- [ ] Preserve existing bookmarks, memorization plans/results, settings and reading position; add versioned storage without replacing old stores.
- [ ] Keep original Quran text, QCF V2 fonts and authored line/word metadata unchanged.
- [ ] No pretend buttons, guessed verse bounds/tajweed, unproven speech scoring, or unsupported sync claims.
- [ ] Original calm unified RTL identity, readable type, uncluttered hierarchy, 44pt controls, reduced-motion support, dark mode and VoiceOver.
- [ ] Current native screenshots for all changed screens and interaction states retained for final review.

## Sequential acceptance
1. Reader layout and alignment
   - [ ] Entire page centered in actual safe reading area after toolbars; exact aspect ratio, no clipping, no unjustified margins.
   - [ ] Surah headers, basmala, ornaments, authored rows, ayah markers and page number straight and balanced.
   - [ ] One-tap tools with invariant page frame; quiet RTL page turns; gestures separate from long-press selection.
   - [ ] Multiple compact/large iPhones, tools hidden/shown, landscape, zoom and return, exact last-page restoration.
2. Verse interaction and tajweed
   - [ ] Actual glyph hit regions and gentle segmented highlighting for multi-line verses, no adjacent-verse coverage.
   - [ ] Dismiss selection; usable tafsir/audio/repeat/bookmark/memorize/recite actions without obscuring selected verse.
   - [ ] Validate reliable tajweed data against exact Uthmani/QCF rendering; preserve diacritics/rows; toggle and legend only when verified. Otherwise keep unavailable implementation hidden and record concrete missing data.
3. Memorization/recitation inside reader
   - [ ] Surah/page/verse-range selection and start within reader, mic status, pause/finish controls.
   - [ ] Hide/reveal selected verses while controls stay visible; reveal/audio help counted in results.
   - [ ] Persist sessions, goal/progress/review recommendations, repeat range/count/gap.
   - [ ] Verified Arabic audio analysis only; low-confidence/noisy input never reader error; no unproven tajweed claims.
   - [ ] Complete self-recitation mode when reliable analysis unavailable; denial/network/interruption/resume tested.
4. Khatmah journey
   - [x] Implement start/current page, daily amount/deadline, weekdays/reminder, actual 604-page schedule and preview.
   - [x] Implement direct reader entry, explicit last-completed-page confirmation, unique progress and reread sessions.
   - [x] Implement versioned atomic persistence, pause/resume/edit with old sessions preserved and completed-plan history.
   - [x] Implement explicit missed-day redistribution/extension preview, no silent plan alteration.
   - [x] Implement serialized scoped reminder replacement and reader deep-link.
   - [x] Native calculator/persistence/reminder-plan/export/erase tests accepted at 7efdb6e; latest integration regression still pending.
   - [x] Actual UI confirms correct progress, rendered reader entry without increment, pause/resume and relaunch persistence at 7efdb6e on compact/large; visual review pending.
   - [ ] Notification permission/cancellation/no duplicates verified; delivery limitations stated accurately.
5. My journey
   - [x] Implement main khatmah/next-portion/finish card, daily confirmed-reading timeline, tappable monthly reading calendar and session detail.
   - [x] Implement concise reading/memorization summary with actual history link, finished journeys with start/end, truthful empty states.
   - [x] Reuse short calm transitions/progress updates and reduced motion.
   - [ ] Native calendar/rereading/history tests, compact/large UI and visual review accepted.
6. Dates and time
   - [ ] Prayer viewed day/day name, Gregorian and region-suitable documented Hijri calendar.
   - [ ] User/viewed timezone drives date and prayer day; rollover/location/timezone changes tested.
   - [ ] English 0–9, 24h HH:mm, isolated numeric direction consistently on home/prayer/reminders/widgets.
7. Remove requested features
   - [ ] Remove compare-verses and verse-reflection UI/routes/search/shortcuts/unused logic; old links/notifications safely redirect to reader.
   - [ ] Remove Friday settings/options/scheduling and cancel old requests without deleting Kahf or salawat content.
   - [ ] Apple account only; remove Google login; remove madhhab/calculation-method UI and preserve automatic location calculation.
   - [ ] Remove user-facing source/rights/disclosure copy requested previously; never remove necessary bundled license material blindly.
8. Khatmah around your day
   - [ ] Same plan, selected after-prayer stations, editable balanced page ranges with no gaps/duplicates.
   - [ ] One next-station home card and reader entry, early finish/merge/postpone without conflicting plans.
   - [ ] Optional prayer-offset reminders, cancel completed station; no prayer-performance requirement or guilt/streak-loss copy.
   - [ ] Finished journey summary and opt-in share card excluding personal information by default.
9. Home and navigation
   - [ ] Resume-reading main card, next prayer/countdown, morning/evening adhkar, one salawat/dua, compact active memorization progress.
   - [ ] Few clear tabs; memorization/recitation part of reader; no duplicate/decorative card clutter.
10. Settings/account
   - [ ] Prominent account/login card at top, actual before/after state/manage/signout; basic reading works without account.
   - [ ] Actual supported sync claims only; organized account/reader/prayer-location/notifications/appearance groups.
11. Widgets
   - [ ] Next prayer, short dua, salawat, resume reading where supported; suitable sizes, clear Arabic and no truncation.
   - [ ] Correct deep links and fresh prayer timeline with iOS refresh limitations.
12. Reminders
   - [ ] Independent prayer/dua/adhkar/salawat/memorization toggles, schedule/frequency/quiet hours.
   - [ ] Replace old schedules safely; no duplicate/old notifications, correct timezone/location/time and deep links.
   - [ ] Visible permission state/system-settings action; real-device checks marked pending until executed.
13. Final review
   - [ ] End-to-end launch/resume/page turn/selection/tajweed/memorize/recite/login/widgets/notifications.
   - [ ] Preserve migrated data and verify relaunch, denied permissions, interrupted sessions and no new crashes.
   - [ ] Latest compact/large screenshots for screens and interactions; no mockups or old captures presented as current.
   - [ ] User reviews final images/result before any publication. Existing App Store build 15 is untouched during this work.

## Current verification checkpoint (2026-10-08 Asia/Riyadh)
- Khatmah native acceptance run 37689367146 at 278ab5b passed compact and large: schedule/persistence tests plus preview, explicit progress confirmation, reader entry without increment, pause/resume and relaunch. This predates reminder/export additions and stronger rendered-page capture checks; not final acceptance.
- Run 37691404097 at daf05c3: compact passed, large UI remained on Home after unconditional swipe/tap. UI fixture 1812413 scrolls only when card is not hittable, verifies arrival, and stops at first failure. Run 37693664854 subsequently passed on both sizes.
- Khatmah runs 37691991015 (f82eace), 37692132299 (4950615) and 37693116524 (7efdb6e) passed compact/large. The last includes rendered-reader readiness; calculator/persistence/reminder budget/DST/export/explicit erasure tests passed. Real notification delivery and visual acceptance remain pending.
- Local app/tests/workflow match remote 0d8f230; local implementation checkpoint 10e53f7. My Journey run 37696464577 failed during compilation: NoorJourneyIndex.swift:13 exceeded Swift's type-checking time for chained flatMap/map/sort. Replaced it with explicit typed collection and sorting, preserving identical dates/IDs/order and stored data. New native acceptance 37699564422 and full checks 37699564480 are pending. No My Journey behavioral acceptance claimed yet.
- Standard Intel macOS native acceptance is enabled for the journey matrix after observed arm64 runner-capacity queues. This changes runner allocation only; real Xcode/simulator tests and original screenshot export remain. Superseded jobs in this branch cancel through scoped concurrency; other branch workflows are untouched.
- Reader run 37693116607 failed an orientation assertion after settled landscape layout. The assertion compared raw CGImage dimensions without UIImage orientation metadata. Fix 5bb6b3c captures the original full screen before asserting and checks displayed dimensions with quarter-turn metadata; native validation remains pending. No rotation/cropping/reconstruction of original image bytes and no visual acceptance claimed.
- My Journey uses only actual confirmed sessions, groups by user-local days, preserves old plans, and never converts generic wellness journeys or opening a page into completed Quran reading. Added leap-year/DST/local-midnight/unique-progress tests. UI verifies saved timeline/detail/month/day interactions. None claimed passed until native result.
- 17 local Python script tests passed. These do not substitute for native behavior tests.
- Actual khatmah screenshot artifacts cannot be downloaded through the current browser due to an explicit protocol restriction; do not retry via indirect routes. No khatmah images have been visually accepted. User-provided screenshot ZIPs can be inspected normally.
- User cannot supply screenshots while sleeping; continue independent implementation/native verification and defer visual acceptance. Do not route around the explicit download restriction. No final review or publication. Existing App Store build 15 untouched.
