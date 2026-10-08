# Noor Alruh production acceptance — active work

This is an execution checklist, not a release approval. The existing brand,
Quran text, QCF edition, user bookmarks and historical sessions are preserved.
No App Store publication before the user's final review.

## Ordered gates

1. **Mushaf system**: 604 native pages; glyph ink/line bounds; authentic header,
   basmalah and short-page layout; fixed geometry during selection, hiding and
   tool transitions; consistent selected verse, heading, tafsir and audio;
   compact/large iPhone interactions; contact sheets and visual inspection.
2. **Inline recitation**: actual microphone permission and capture, separate
   writer/converter/inference/alignment/journal; recognized-only reveal; pauses,
   repeated phrases, distant returns, interruptions, weak audio, storage failure,
   cancellation and resume. No pronunciation/Tajweed grading claim.
3. **Recordings/results/goals**: real playback and seeking after relaunch;
   export/delete; range/date/duration; timed recognition vs unresolved positions;
   actionable review; concise goal setup, daily target and review days; preserved
   legacy history with truthful labels.
4. **Prayer/notifications**: permission denial and location updates; last valid
   location; all five prayer switches; no calculation-method UI; deduplicated
   rebuilt schedule for date/time-zone/location changes; bundled short adhan,
   in-app full audio; English digits and 24-hour clocks throughout.
5. **WidgetKit**: next prayer, reading target and khatmah, home and lock sizes,
   shared storage, actual timelines, stale/unavailable state, RTL, appearance and
   route/reading-position deep links.
6. **Apple account/onboarding**: welcome once, Apple sign-in/create profile,
   returning account, guest reading/progress merge, sign-out, deletion, truthful
   synchronization; microphone/notification/location system permission states.
7. **All screens and final journeys**: home; Quran index; Mushaf; verse toolbar;
   tafsir; repeat/audio controls; recitation; scope; results; recordings/player;
   memorization goal/practice/history; khatmah setup/preview/recovery/history;
   adhkar index/list/session; prayer/city/notification controls; account; welcome;
   settings/privacy; library/bookmarks; My Journey; focus screens/extensions.
   Also every sheet, dialog and navigation return route. Preserve removal of
   Friday settings, Compare verses and Pause with an ayah.

## Verified evidence so far

- Native engine investigation run 19 (`37811954240`): continuous 44.1/48 kHz
  resampling duration and changing-signal checks passed, alongside prior gates.
- Native engine investigation run 24 (`37815303872`, source `b6c98e9`): journal
  reopen/corruption protection and restored timed evidence checks passed.
- iOS integration run 1 (`37816543030`, source `40a75a7`): two actual iOS tests
  passed. The bundled Core ML model recognized timed Quran anchors from the
  identified professional reference recording and silence produced no reveal.
  Independently written CAF bytes and metadata reopened successfully, decoded
  with exact sample count/duration and prepared for playback. This is not a
  live microphone journey or a completed audible playback test.
- Reader run 12 (`37809573717`) failed the normalized surah-name assertion.
  The next test uses exact verified corpus spelling and independently checks
  selected-verse identity; it does not loosen the ayah correctness gate.
- Reader run 13 (`37814355192`, source `56159fa`) completed successfully on
  both iPhone simulator sizes, including the 604-page layout gate and actual
  selection/tafsir/navigation/reading restoration journeys. Current Codemagic
  build 6 (`6ac7d435546ce6236ceca23d`, source `4eb3429`) remains queued.
- Codemagic build 4 had real AAC playback test failures. Build 6 retains actual
  AVPlayer diagnostics and captures both phone UI journeys even if an audio
  gate fails. It does not turn failed assertions into success.

## Remaining evidence boundaries

- No physical iPhone is attached to this execution environment. Actual adhan
  delivery/sound, microphone and interruption acceptance on hardware remain
  outstanding and cannot be substituted by simulator results.
- No complete current live-recitation walkthrough video has been captured.
- The current source replaces the old inline manual-disclosure/self-evaluation
  panel with real recognition controls and stable reader insets. Native compile,
  microphone-denial interaction and new archive/export tests are running; source
  integration alone is not completion. Complete live session proof is pending.
- Final screenshots must come from the implemented app at the final tested
  revision; old screenshots and generated illustrations are not acceptance.
- QCF companion publication rights remain subject to the existing release gate.
