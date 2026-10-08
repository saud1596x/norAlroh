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
- [ ] Review all contact sheets and individual suspicious pages.
- [ ] Inspect actual reader captures on two iPhone display classes, tools
      visible/hidden, selection and zoom; no cropped marks or layout movement.

## 2. Recognized recitation

Native investigation checkpoint: runs `37776925812` and `37777735599`
compiled the pinned WhisperKit probe and executed the real Quran Core ML model
on an Apple runner. The first rejected invalid silence timing. The second
retained the raw report and rejected two control windows. This is a failed
engine acceptance gate, not a working inline recognition feature. Report loss
on async-main trapping has been corrected without removing either rejection.
The live microphone, whole-corpus word correspondence and iPhone validation
remain outstanding. QUL's official word-script download requires sign-in;
do not scrape previews or use guessed compound boundaries to bypass that gate.

- [x] Current source inspected: independent local audio recording exists; no
      functioning recognition engine is connected to the inline study session.
- [ ] Validate the selected Quran-specific engine on native Apple execution,
      including real phone recitation and recognition failure.
- [ ] Record audio independently of recognition/alignment; bounded inference,
      accurate take-relative timestamps and durable recovery.
- [ ] Validate Unicode-word to exact QCF-word identity across the entire corpus.
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
  `0338074ac8d662f6f52c5d66b433cac74202158e` (metadata inspected; not executed).

Reference audio investigation uses existing-app EveryAyah URLs. Professional
recordings and assembled repeat/silence/noise signals are not a live session or
an independent beginner-recitation benchmark.
