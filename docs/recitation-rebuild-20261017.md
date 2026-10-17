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
and a real UI search/selection/persistence journey. These are **pending**, not
passed. Injected PCM transport is not an iPhone microphone test.

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
