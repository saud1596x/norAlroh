# Additional learner-engine scope — 18 October 2026

User order: learner microphone engine, all professional-reader word/ayah
following, then private TestFlight. Subsequent paid CI/beta budget: USD15.
This ledger is a delivery contract, **not a list of implemented features**.
Existing capture, VAD, bounded gain, original recording, cancellation, offline
model, exact-word alignment and source provenance are baseline and do not count
as new additions. Tests, libraries, numerical thresholds and logging alone do
not count as user features either. No separate recitation/history screen.

`P` = planned, `E` = experiment, `I` = integrated but not fully verified,
`V` = implemented with the stated verification. Production/learner acceptance
must still be reported separately. Never infer V from a checked box or a model
publisher's benchmark. Evaluation uses unprompted acoustic hypotheses;
professional forced alignment must never adjudicate a learner.

| ID | Additional behavior | Required acceptance | State |
|---|---|---|---|
| 01 | Independent Quran CTC recognition opinion | Real PCM raw output without reference text; pinned assets | E |
| 02 | Agreement from two independent recognizers | Same actual source-word interval; measured disagreement abstention | P |
| 03 | Suppress correction when recognizers disagree | Disagreement cannot become a confirmed learner error | P |
| 04 | Retry a low-confidence word with its genuine audio context | Bounded retry, original clock and original rejected hypothesis retained | P |
| 05 | Stable partial-word display | Revisions cannot flicker already committed words | P |
| 06 | Recover words straddling decode windows | Real continuous utterance, no duplicated word/progress | P |
| 07 | Track deliberate repetition of the same ayah | New audio occurrences, no forced jump to another shared verse | P |
| 08 | Track deliberate return to an earlier ayah | Independent distinctive acoustic anchor; preserve previous evidence | P |
| 09 | Handle a learner's immediate self-correction | Retain both attempts and retract only the provisional discrepancy | P |
| 10 | Distinguish repeated word from insertion | Genuine occurrence and context; never double award progress | P |
| 11 | Distinguish hesitation from omitted word | Pause alone cannot create omission | P |
| 12 | Recover from a mid-ayah start | Full-corpus unique evidence, no guessed preceding words | P |
| 13 | Recover from a mid-word start | Incomplete first word stays unassessable | P |
| 14 | Recover after an interrupted word | No bridge over missing acoustic evidence | P |
| 15 | Recognize verse joins across pauses | Same next-ayah evidence with bounded gap and no forced continuation | P |
| 16 | Recognize spoken opening letters | Verified spoken aliases; display Quran bytes unchanged | P |
| 17 | Distinguish an introduction from Quran progress | Istiadhah/control clips produce no false Quran confirmation | P |
| 18 | Handle opening basmalah without wrong-surah jump | Ambiguous basmalah abstains without distinctive continuation | P |
| 19 | Detect clipping bursts separately from sustained overload | Actual normalized PCM and no false error grading | P |
| 20 | Detect a sustained DC offset in microphone input | Original PCM unchanged; bounded signal diagnostics | I |
| 21 | Remove measured DC offset from inference copy | Unchanged frame clock and real-audio recognition comparison | I |
| 22 | Detect disconnected/frozen microphone samples | Deterministic flatline evidence, not silence guessed as failure | I |
| 23 | Identify intermittent audio dropouts | Time-bounded loss indicators without filling missing speech | P |
| 24 | Avoid gain pumping from brief loud transients | Quiet speech+click controls; no clipping or timing shifts | P |
| 25 | Distinguish usable quiet speech from stationary noise | Real speech/noise held-out diagnostic and abstention | P |
| 26 | Cancel persistent signal advice after recovery | Hysteresis; brief healthy block cannot hide repeated fault | I |
| 27 | Maintain signal guidance across overlapping decode windows | Count capture time once, not duplicated ASR windows | P |
| 28 | Detect out-of-range PCM before recognition | Invalid amplitude never becomes accepted word evidence | I |
| 29 | Handle a bounded long held vowel without duplicate words | Genuine sustained speech, no duration-based correctness claim | P |
| 30 | Support slower recitation without losing the current position | Real slow recordings, bounded context/memory | P |
| 31 | Support faster recitation without dropping leading words | Real fast recordings and explicit overload behavior | P |
| 32 | Pause location uncertainty without resetting listening | Same inline UI, preserved genuine source evidence | P |
| 33 | Show a concise reason for tracking uncertainty | Distinguish signal, recognition disagreement and ambiguous location | P |
| 34 | Show pending recognition separately from captured input | Actual capture/worker state; no decorative success pulse | P |
| 35 | Prevent stale advice on resume or route change | New take/route invalidates prior diagnostic state | P |
| 36 | Give a single actionable inline signal hint | No extra screen or stacked diagnostic cards | P |
| 37 | Delay discrepancy indication until later independent context | Evidence revision test and bounded pending state | P |
| 38 | Retract a provisional discrepancy after better evidence | Real source revision, durable original observation | P |
| 39 | Avoid alerts on the same unchanged discrepancy repeatedly | Stable occurrence identity with measured cooldown | P |
| 40 | Keep uncertain pronunciation separate from wording | No unvalidated phonetic/Tajweed verdict | P |
| 41 | Detect recognizer drift on long pauses | No hallucinated continuation in real pause/noise audio | P |
| 42 | Recover location after a long unrelated utterance | Independent fresh anchor, no expected-text prompt | P |
| 43 | Reject uncertain mixed-speaker overlapping speech | Real overlapping speech challenge set; honest abstention | P |
| 44 | Preserve nearest actual acoustic boundary in a retry | Exact frame provenance and no inferred word intervals | P |
| 45 | Compare model versions on the same frozen audio cases | Per-case regressions, not aggregate improvement alone | P |
| 46 | Measure correction precision on reviewer-labeled real mistakes | Separate held-out natural learners; no public-label substitution | P |
| 47 | Measure false alerts on valid recitation | Reviewer labels and device/environment slices | P |
| 48 | Measure first-word latency separately from warm throughput | Original capture timestamp through inline highlight | P |
| 49 | Maintain bounded performance during sustained recitation | Long actual session with latency/memory/thermal measurements | P |
| 50 | Safe model fallback after independent-engine failure | Exact source identity, no replay/late result from retired engine | P |

Items requiring natural learner audio/reviewer labels/device measurement remain
unverified until that evidence exists. Artificial faults can exercise failure
handling but cannot establish general recognition or religious correctness.
No new model is shipped, no private audio uploaded, and no reader candidate is
promoted merely by writing this ledger.

## First implementation batch

Five additional behaviors are integrated above; their current native tests have
not run. Existing per-take guidance reset/inline placement is preserved and is
not counted again. Local Python tests:14passed, including actual pinned112:1
audio at3%gain with an injected0.15DC fault, compared against the same unaltered
clip. The input array/frame count stays unchanged and constantDC produces no
recognized words. This is a known public diagnostic, not natural-learner quality.

The independent CTC experiment exported pinned weights to a development-only
FP16ONNX artifact (SHA256in`quran_onnx.py`). Raw greedy words matched the original
FP32CPU model on22public audio/control cases; both returned empty controls.
Actual CUDA node execution was profiled. Warm median was31ms on the existing
localRTX5060; cold inference took23.094s and cuDNN emitted plan warnings before
fallback. Maximum frame posterior difference was0.2568 despite identical word
strings. Thus conversion parity is **not posterior calibration, production
acceptance, iPhone speed or accuracy improvement**. It is not wired into the
shipping provider, nor may its forced alignment mode assess a learner.
