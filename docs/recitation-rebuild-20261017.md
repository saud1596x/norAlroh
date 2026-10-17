# Continuous Mushaf rebuild — implementation and validation in progress

This work is not a production accuracy certification. Build22 predates it.

## Root causes and integrated changes

- Stop automatically presented QuranSessionResult; manual result entry points
  also paused recording. The screen and those routes are removed. Stop keeps
  the current page, selection and silently persisted session.
- Visible-text tracking hid the remaining Quran as soon as any word was found.
  Only explicitly requested closed-text practice may now hide words.
- Five verse reciters were persistent choices; twenty whole-surah entries were
  temporary play buttons. Both catalogs now use one searchable selector with
  stable recording identities, persisted preferences and the reader's player.
  Whole-surah recordings remain honestly labeled and never receive invented
  verse boundaries. Preference changes do not play media or release capture.
- The legacy switch method accepted a stale five-directory list and omitted
  current published bitrates. It now validates the actual directory catalog.
- Manual page turning disabled the shared follow flag indefinitely, blocking
  later Quran-wide navigation. A new accepted live verse may navigate again;
  draining after Stop cannot move the page.
- Corpus retrieval compared a union of all candidate starts against every heard
  offset, even when their first tokens differed. Lookup is indexed per heard
  starting token, retaining the exact matching/ambiguity policy.
- Silence reached model preparation and inference. Pinned WebRTC VAD, mode0,
  now detects speech intervals locally before model work. It changes neither
  saved PCM nor timestamps. VAD failure falls back to normal recognition; it
  is not a calibrated confidence, noise guarantee, or pronunciation verdict.
- Revisited pages repeated Core Text shaping. A three-page cache validates the
  complete authored page and appearance, excludes session highlights, and
  rebuilds accessibility with the current canonical corpus. Gesture boundaries
  also respect daily reading ranges.
- Guided replay from an automatic session could enqueue all6236 verse keys.
  Its inline retry now plays the current verse. Assistance records the actual
  recording identity rather than an unrelated default voice.
- Model loading returned a non-Sendable WhisperKit instance through a task.
  Loading now returns Void and retains the instance inside its owning actor.

## Verification scope

Local source-copy verification: all6236 verses and112 separate basmalas match
the pinned canonical source exactly. New Swift syntax and YAML parse locally;
that does not replace Xcode type checking.

The new native workflow includes real Core Text rendering on all604 pages,
voice catalog identity tests, recording-ownership tests, all ten public VAD
reference clips, same-session Quran-wide recognition from actual public PCM,
and a real UI search/selection/persistence journey. The actual 30c37a6 run
6ad3bf017550aed8108fa51b compiled Release, passed rendering all604 pages in
20.996 seconds, catalog/ownership/VAD,12 viewport,3 worker lifecycle,4 mailbox
and1 capability tests. Its real reciter search/selection UI passed in35.292s.
Overall it **failed**:24/25 unit tests passed; the real PCM case remained at
112:1 instead of114:1 after the second public clip. Injected PCM transport is
not an iPhone microphone test. Evidence is retained in
outputs/continuous-30c37-visible-log.txt outside the repository.

Inspection identified a separate deterministic alignment defect: a rolling
window's independent passages competed for one global longest match. Equal
length passages at different audio positions were treated as ambiguous, and a
long older passage suppressed a shorter later one. Alignment now resolves
alternatives in connected overlapping heard intervals, retaining the strongest
unique exact anchor and existing confidence/timing thresholds, then consumes
independent passages in audio order. A direct regression covers two surahs,
an unresolved common phrase and a stronger overlapping anchor. A subsequent
dad771a run was cancelled before testing after that overlap counterexample was
identified; it is not a test pass.
The original shared alignment suite is also included in the native test target.
Whether this resolves the real PCM failure is **pending**. Failure attachments
now retain actual public-fixture observed words and timing for diagnosis.

## Acoustic limitation and measured research

The deployed WhisperKit backend supplies words and timings, not independently
verified phonemes or Tajweed attributes. Its wording events remain provisional.
No confirmed error rate, Tajweed precision/recall, or professional accuracy can
be claimed from that backend.

A separate local experiment actually executed the pinned phonetic model
TBOGamer22/wav2vec2-quran-phonetics, revision
65c3ab93446f2f1041a18082433a911e5e154a9d, on ten public references, silence,
quiet and noise derivatives. Windows CPU inference ranged approximately
0.17–0.44 seconds. Its raw hypotheses are saved in
outputs/phonetic-candidate-benchmark.json outside the repository. Those are
timings, not accuracy; no adjudicated phoneme references were used. The model
is not shipped or advertised as a Tajweed evaluator.

Primary model references:
- https://huggingface.co/TBOGamer22/wav2vec2-quran-phonetics
- https://huggingface.co/obadx/muaalem-model-v3_2
- https://github.com/obadx/qdat_bench
- https://huggingface.co/datasets/obadx/qdat_bench

Rule-level correction still needs a validated native phonetic/sifat model,
matching Hafs phonetic references bound to canonical native word IDs, and
calibration/evaluation against independent learner audio. Published model
authors' metrics cannot be reused as this app's metrics. Public benchmark
availability is recorded; it has not yet been evaluated by this app.
# Explicit text visibility control (latest request)

The unrestricted Mushaf now has a labelled eye button before recording and
during a listening/paused session. It hides the authored page text before a
session, or the remaining in-scope words during one; saved recognized words
and explicit hints remain visible. The button neither stops capture nor opens
another screen. The reading-only daily ward is unaffected. Existing VoiceOver
masking prevents hidden verses from being read aloud.

Current visibility is persisted separately from the initial closed-text request.
Showing text permanently marks the session and current take as text-assisted;
hiding it again cannot erase this. An analysis-specific journal merge prevents
delayed off-main inference saves from overwriting newer visibility, assistance
or take-close state. Added regressions cover the live toggle, same capture/take,
reopening, a stale analysis save, VoiceOver masking and the real UI button.
Actual c2c0568 Release run6ad3c2b27550aed8108fa5d5 passed the hide/show UI
journey, same-session/take visibility changes and restored preference,
concurrent visibility/assistance preservation, stronger overlapping-anchor
regression and all8 original canonical alignment tests. All604 pages rendered
in21.132s with VoiceOver masking and non-uniform pixel checks. Overall35/36
unit cases passed and1/1 UI passed; the real PCM case failed4 assertions.

The new analysis-only merge introduced a real regression: it kept the disk's
earlier zero/short take length instead of the window's actual captured frames.
Timed observations therefore failed journal validation and paused capture.
The fix merges monotonically growing frame counts by take ID while preserving
later close/phase/visibility flags. A new regression checks a zero-frame active
take growing to16000 and a later closed32000-frame take resisting rollback or
reopening. This fix is pending native verification; c2c0568 is not a pass.

The user's latest request also reactivates Tajweed colors. QUL's actual matching
V4 layout resource is https://qul.tarteel.ai/resources/mushaf-layout/19 ; this
page explicitly still describes V4 as pending proofreading, while font 240 is
downloadable. Its glyphs cannot be substituted into the app's V2 source. No
color toggle or guessed colors have been shipped; the edition/proofreading and
canonical-word mapping remain unresolved for that feature. The official sample
font CDN returned HTTP403 and authenticated TTF archive downloads did not
produce a file after two bounded waits. Actual blocker evidence is recorded in
outputs/tajweed-font-audit/status.json outside the repository.
# Reader comfort and playback lock — pending native verification

- Replaced the overlaid page-number/microphone ZStack with separate touch areas. The microphone, visibility and More controls occupy one row; page navigation occupies its own row. More exposes the existing scope, recordings, review and khatmah options without requiring a long press.
- Reciter entry has a visible label and the chosen name as its accessibility value. Recitation options use a full-width scrolling sheet instead of a fixed260–320pt popover. Measured session header/footer now include input guidance and the visibility row so they cannot overlap Quran ink.
- Manual page turns, page arrows and page-number jumps lock during this reader's playback/loading/repeat gaps. The viewport clears an in-flight drag when locking. Canonical playback callbacks retain automatic page replacement. Stop unlocks navigation. Whole-surah recordings start on their actual first-ayah page; subsequent word/page tracking still requires recording-matched timing data and is not fabricated.
- Actual22cff73 native result:36/37 unit and1/1UI passed,7m31s. The frame-growth regression passed. Captured ASR evidence contained all eight words from112:1 then114:1, but the old transitive overlap component confused a shorter cross-boundary112/113 prefix with both full anchors. A new optimal non-overlapping anchor selection retains only bindings shared by every best interpretation. The new regression replays those exact captured words/times against the entire authentic corpus; it is not a new acoustic benchmark.
- Visibility now performs a visibility-only atomic merge, preserving newer on-disk word evidence in both disk-write orders. Showing then hiding text cannot erase assistance flags.
- `reader-ease-check` is a bounded7-minute Release native regression for these changes. It does not replace actual-ASR, hardware microphone, full-release, visual approval, all-reciter timing or Tajweed acceptance. No new TestFlight build is claimed.
