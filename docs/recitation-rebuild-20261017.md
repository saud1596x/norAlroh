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
alternatives at each heard offset, retaining exact unique anchors and existing
confidence/timing thresholds, and consumes non-overlapping matches in audio
order. A direct regression covers two surahs and an unresolved common phrase.
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
Swift syntax parsing passed; these additions are **not** in the already-running
30c37a6 native run and are not yet verified by native execution.

The user's latest request also reactivates Tajweed colors. QUL's actual matching
V4 layout resource is https://qul.tarteel.ai/resources/mushaf-layout/19 ; this
page explicitly still describes V4 as pending proofreading, while font 240 is
downloadable. Its glyphs cannot be substituted into the app's V2 source. No
color toggle or guessed colors have been shipped; the edition/proofreading and
canonical-word mapping remain unresolved for that feature.
