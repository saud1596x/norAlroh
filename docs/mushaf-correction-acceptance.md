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

- [x] Current source inspected: independent local audio recording exists; no
      functioning recognition engine is connected to the inline study session.
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
  acoustic/timing gates; not integrated into the app).

Reference audio investigation uses existing-app EveryAyah URLs. Professional
recordings and assembled repeat/silence/noise signals are not a live session or
an independent beginner-recitation benchmark.
