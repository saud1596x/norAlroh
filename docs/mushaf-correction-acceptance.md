# Mushaf and recitation correction acceptance

These are release gates, not completed-feature claims. Preserve existing Quran
text, glyph IDs, reading position, bookmarks, settings, plans and session data.

## 1. Authored page balance

- [x] One shared heading rule measures QCF companion ink and the space between
      actual body ink; scales the complete ornament and title uniformly.
- [x] Body baselines, word advances, line breaks and Quran glyphs are unchanged.
- [x] Native assertions cover all 604 pages, title containment, vowel clearance,
      hidden-word geometry and original-font identity.
- [x] Contact-sheet exporter requires all 604 actual native captures.
- [x] All-page native assertions pass on corrected renderer source `a658dc9`:
      GitHub Actions run `37771657826`, Release, iPhone 16 Pro Max/iOS 18.5.
      All 604 shaped pages and word regions passed; viewport centering and
      snapshot/offline recovery also passed (3 tests, zero failures).
- [x] Reviewed all 13 contact sheets (604 actual UIKit/CoreText captures) from
      Codemagic build `6ac7872b546ce6236cec8595`, source `9714124`, iPhone 17 Pro.
      Investigated the small heading around pages 427/428 in full-resolution
      native images; the title is present and centered. No atlas-level clipping
      or displaced heading was found. This does not replace two-phone UI checks.
- [ ] Inspect actual reader captures on two iPhone display classes, tools
      visible/hidden, selection and zoom; no cropped marks or layout movement.

The Copy feedback fix in `0350ab2` is verified. GitHub Actions run
`37786291016` / source `3d762c6` passed all seven native layout tests and both
complete reader UI journeys on iPhone 16 Pro and iPhone 16 Pro Max (Xcode 26.3).
The source renderer is unchanged from the reviewed 604-page atlas. Downloading
GitHub artifacts is policy-blocked; do not bypass that restriction.

Codemagic build 3 `6ac796f4546ce6236cec8b61` / source `0350ab2` passed all seven
native checks (118.496 seconds, zero failures), Copy feedback, all page-604 verse
selections, tafsir, RTL page turning and restored reading after relaunch on
an iPhone 17 Pro. Reviewed its actual fresh page, highlighting and Copy captures.
The complete canvas pixel crop is identical with tools shown and hidden.
Its reader journey failed at line 71 while remote AVPlayer was still waiting
for EveryAyah media; there was no load deadline. The larger phone did not run.

`MushafVerseAudio` now cancels an initial or stalled stream after 15 seconds,
releases audio ownership and presents a retry/offline-download message.
A real local nonresponding HTTP source tests the deadline, plus existing real
AAC repetition/end/replacement tests. The UI requires actual playback or a
visible bounded connection failure, then continues zoom/reselection; failure
captures are explicitly named as failures, never successful playback.
Codemagic build 4 `6ac7ad0c546ce6236cec93be` / source `1d46f7d` is queued.
The deadline and updated two-phone journey are not yet verified.

## 2. Recognized recitation

The supplied original `imlaei-simple.json.zip` is validated against its
pinned JSON hash. All 6236 verses / 77,429 authored word groups now bind by
verse and position, never cross-database numeric IDs. Three explicitly reviewed
بعد ما compounds (2:181, 8:6, 13:37) retain one original glyph group and require
both spoken tokens. Actual native page captures and the QUL source test verified
these boundaries. Canonical Tanzil aliases also retain the single 37:130
ال ياسين group. Any unexpected boundary, page or glyph change rejects binding.
The script is lexical-only; Quran display text, lines and geometry are untouched.

Native run `37794809248` / source `1d46f7d` passed four acoustic-evidence tests
and six alignment tests, including actual all-6236-verse binding, edition
corruption rejection, repetition/return, ambiguous anchors and low confidence.
It executed 32 real Core ML windows and retained both raw words and exact timed
Quran anchors. Silence/noise created zero accepted progress. Raw model output
still hallucinated an out-of-clip word, which was rejected rather than hidden
from the diagnostics. This is a conservative tracking pipeline, not a validated
pronunciation/Tajweed grader or live iPhone acceptance.

The first actual anchoring run exposed a missing ordinary spelling of dagger
alif in الرحمن and إله. The binder now accepts both authoritative imlaei and
literal/expanded canonical forms, without deleting written long vowels or fuzzy
letter substitutions. The follow-up native run must confirm the correction.
Live microphone integration, durable timed session storage and iPhone behavior
remain outstanding; diagnostic passes do not complete the shipping feature.

- [x] Offline native recognition, independent PCM capture, exact alignment and
      durable journals are connected to the inline reader. This is implemented
      source, not acceptance of live microphone accuracy.
- [ ] Validate the selected Quran-specific engine on native Apple execution,
      including real phone recitation and recognition failure.
- [ ] Record audio independently of recognition/alignment; bounded inference,
      accurate take-relative timestamps and durable recovery.
- [x] Validate Unicode-word to exact QCF-word identity across the entire corpus.
      Standalone pause marks and compound written words cannot be mapped by a
      naive space split.
- [ ] Reveal only actually recognized, adequately supported words. Handle
      repetitions, corrections, backtracking and pauses without timer reveal.
- [ ] Start/pause/end are the primary controls; secondary options in one menu.
- [ ] Uncertain recognition is never a confirmed recitation error. Do not claim
      pronunciation or tajweed grading without an independently validated engine.
- [ ] Permission refusal, interruption, resumption and recognition/save failures
      have tested behavior and truthful visible states.

## 3. Recording retention and playback

- [ ] Actual scrubber, pause/resume playback, replay, share and confirmed deletion.
- [ ] Metadata includes surah, range, date, duration and actual audio take IDs.
- [ ] Saved audio and session metadata play correctly after app termination.
- [ ] Failed save or corrupt audio does not silently erase the original bytes.

## 4. Results and goal

- [ ] Compact visual result: actual range, duration, supported progress and
      confirmed errors separately from unresolved positions; no invented score.
- [ ] Relevant positions open in the reader and the actual timed recording.
- [ ] Short goal setup, preview and confirmation; progress and one session action.
- [ ] Review suggestions come from retained session evidence. Keep legacy
      self-assessed data labelled with its original source.

## 5. Motion and final journey

- [ ] Shared restrained transitions, stable Quran geometry and Reduce Motion.
- [ ] Two-iPhone full-session test: start, pause/resume, repeat/correct, finish,
      relaunch, play, review. Verify refusals and failure paths.
- [ ] Fresh actual screenshots of implemented interaction states and an actual
      app-session video; identify any prerecorded test-audio input honestly.
- [ ] Reviewable branch, exact build source and test results delivered.
- [ ] User reviews before publication. Do not publish from a partial gate.

## Investigation boundaries

An isolated CPU investigation of the Apache-2.0 Quran Whisper conversion found
extra trailing tokens and omitted repetitions in long-context transcription.
Short overlapping windows also produce partial-word mistakes. This is useful
failure evidence, not iOS accuracy, beginner accuracy or grading validation.
Do not connect the raw transcript directly to successful-progress/error labels.

Investigated model revisions:

- `OdyAsh/faster-whisper-base-ar-quran`:
  `8578bafd427d122f671b187706650e76edf6f86f` (CPU investigation only).
- `fazalshaikh123/ultra-fast-tarteel-coreml`:
  `0338074ac8d662f6f52c5d66b433cac74202158e` (executed on a native Apple runner;
  raw silence/noise hallucinations retained and rejected by independent
  acoustic/timing gates; the pinned model is now integrated into the app).

Reference audio investigation uses existing-app EveryAyah URLs. Professional
recordings and assembled repeat/silence/noise signals are not a live session or
an independent beginner-recitation benchmark.

## Current verification checkpoint — 2026-10-08

The earlier investigation notes above describe their original revisions. Use
this checkpoint for the latest status; no failed test is relabelled as a pass.

| Gate | Exact source and run | Observed result |
| --- | --- | --- |
| All 604 native pages and two complete reader UI journeys | `56159fa9b8fd455e4906642e451ca9d534be4b72`, Actions `37814355192` | Passed, 37m 47s. Includes authentic selection, heading, tafsir, copy, playback-or-visible-failure, zoom, RTL turn and reading restoration. |
| Acoustic and exact alignment investigation | `1d6ddc6`, Actions `37818345557` | 16 tests, zero failures; real 32-window professional-audio inference and silence rejection. |
| Single complete authored group | `14a85dc5622a8b5b56cf29738e7f31184d6f61e8`, Actions `37830443451` | Passed. Strong-confidence exact matching is tested; no claim about live one-word recognition accuracy. |
| Native bundled resources, CAF reopen/export, genuine model/silence, denied capture | `05475278436f1c27fcebc0b948d2ae9cba90b4ec`, Actions `37828351851` | Passed, including actual OS microphone refusal and restored reader controls. |
| Stable actual page/reveal accessibility, compact scope selection, OS denial | `e1d691838d44c5147198b232df805ec023d0301e`, Actions `37830571667` | Passed, 13m 29s. Page/surah/range scope and actual native canvas are exercised. |
| Controller start/pause/reopen/resume/end, retained actual reference PCM; startup failure; late permission cancellation; real invalid AVPlayer input | `7c9ee97373d1f624b7fbcd7fb778ad775ed3840e`, Actions `37832540906` | Passed, 15m 29s (native job 13m 5s). Eight native integration tests and three focused UI tests passed. Reference audio is explicitly a fixture, not live microphone acceptance. |
| Codemagic all-pages and two phones | `4eb34290a120d9f05b016f0c4bc13171ab001347`, build `6ac7d435546ce6236ceca23d` | Failed. All-page shape/viewport and atomic offline recovery passed. Real AAC repetition had 7 assertions fail with HAL proxy 268451843/268435460 and zero advancing player time. Compact UI did not expose playback or failure within its deadline; large UI exposed `reader.load.error`. Actual artifacts retained and inspected. |

Codemagic's old source predates shared mandatory font/manifest staging and the
unified reader alert. Its audio-route failure is not proof of correct playback.
A newly injected real missing-file playback UI test must verify the alert path;
no successful status or manual word disclosure is substituted for AVFoundation
or recognition. Codemagic artifacts are accessible by ordinary UI download;
GitHub artifact and raw-log download restrictions must not be bypassed.

Implementation completed so far includes exact partial-ayah coverage, a concise
page/surah/range chooser, a direct microphone action, stable hidden glyphs and
honest uncertainty. Results omit playback when no nonempty take was retained.
Real physical microphone, interruption, Bluetooth, audible playback and
beginner-recitation behavior remain unverified. The current engine tracks
positions and never labels pronunciation or tajweed errors.

## Remaining latest-request gates

Proceed one stage at a time; existing user progress and old session bytes remain
intact. Never replace legacy self-assessment with purported automatic evidence.

- [ ] Finish recording transport: actual seek, pause/resume, replay, share,
      recoverable deletion, timestamp review and reopen persistence.
- [ ] Connect concise memorization goals, daily amount/review days, preview,
      session start and evidence-based history/review; retain legacy access.
- [ ] Location-aware five-prayer notifications, no duplicates, timezone/date
      rescheduling, pinned valid short adhan and full in-app playback.
      Verify real notification sound on a physical iPhone.
- [ ] Actual home/lock WidgetKit layouts, shared timelines/deep links, next
      prayer, reading target and khatmah progress, stale/location-denied states.
- [ ] First-launch Apple-only sign in/create-profile, guest reading, onboarding
      persistence, profile restore, sign-out, deletion and only real sync.
- [ ] Inventory and review every screen/route; preserve Friday-setting removal,
      Compare verses removal and Pause with an ayah removal. Keep Quran content.
- [ ] English digits/24-hour clocks throughout app and widgets, Arabic RTL,
      VoiceOver, Reduce Motion, dark appearance and minimum touch areas.
- [ ] Verified final source/build with actual screenshots of every updated
      screen and a real full-session walkthrough including recording playback.
- [ ] Resolve existing release-rights gate for original common font/layout.
- [ ] Present verified result to the user before App Store publication.

### Recording transport implementation checkpoint

Added actual AVAudioPlayer pause/resume, clamped seeking, replay and its real
playback position to the recording screen. Audio interruptions and leaving the
foreground pause playback without auto-resuming. Removed repeated explanatory
sections from the recording list. File sharing uses the existing original URL.
Recoverable removal moves each original audio file into DeletedAudio; restoration
refuses to overwrite live audio. Sessions remain reachable when every take is
removed, and exports include removed-take metadata. Recognition journals are
not rewritten by any playback or removal operation.

New native tests exercise real AAC transport and a newly created player's
reopening, plus byte-identical removal/restoration and unchanged session metadata.
These additions are pending native execution; they are not UI relaunch, audible
physical-device output, or full-session video acceptance.

Recording transport source `24cd6afde24731e90389e0efad755998416d896c`
passed Actions `37836235673` (10m 32s overall / 10m 23s native job):
13 recording tests, eight reference-recognition integration tests and three
actual reader UI tests. This proves native transport/recovery, not the new
recording screen's interactions or physical-device audible playback.

The next focused UI gate uses repeated authentic `112001.mp3` reference audio
in a simulator-only persisted session, with no microphone or ASR result
fabrication. Its artifact `recording-ui-fixture.json` identifies that limitation.
It exercises the actual app's history, player, seek/pause/replay, recoverable
removal, relaunch, restoration and playback. Exported video is named
`reader-and-recording-ui.mp4`, not a claimed live recitation walkthrough.

Recording-history source `25d9e3b048966762778cd1ba1569dd63184eed3f`
failed Actions `37838479112` in 5m 58s before tests: the catch's implicit
immutable `error` shadowed the recording browser's message state at
MushafStudyViews.swift:302. The concrete fix uses `self.error`; source
`56476f0c37eb33b5046351c48883af17a82df120` is under native Actions
`37839688034`. New UI screenshots/video are not yet verified or delivered.

Codemagic recitation build `6ac7f19a546ce6236cecace5`, source `7c9ee97`,
remains queued without machine provisioning or checkout logs. Billing shows
402 / 500 free macOS minutes used; no subscription was enabled. This is not
a claim that the branch or YAML is failing to load.


### Actual recording UI gate — current status

Actions `37839688034`, source `56476f0`, finished **failed** after 13m 40s:
all 13 native recording tests and eight recognition integration tests passed;
three reader UI journeys passed, but the persisted reference session was absent
from the recording history. Transport/relaunch UI acceptance is therefore open.
No new screenshot or video is represented as final application acceptance.

The next source creates the identified reference CAF using AVAudioFile in the
native hosted test and production MushafRecordingArchive.root(), verifies it
can be reopened through production archive code, and writes the exact resolved
container path for the script to validate. The UI assertion now reports the
actual accessibility tree if the reference remains absent. This removes manual
storage-path assumptions and preserves the UI gate rather than skipping it.
Source `1f7a2b2de110200950c764ce5a56f47b7f3784b5` is under Actions
`37841634686`; it is not yet passed.

The stale queued Codemagic build 2 was canceled before a machine was allocated.
Build 3 `6ac7ff13546ce6236cecb1ae` uses source `9bccaaf` (the same app code
as `56476f0`, plus verification notes), and remains queued. Its pending gate
still includes the identified reference-fixture failure; no artifact is ready.
