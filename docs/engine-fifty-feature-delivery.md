# Additional learner-engine scope — 18 October 2026

User order: learner microphone engine, all professional-reader word/ayah
following, then visual Mushaf balance/centering, comfortable reading and Tajweed
colors, then private TestFlight. Subsequent paid CI/beta budget: USD15.
This ledger is a delivery contract, **not a list of implemented features**.
Existing capture, VAD, bounded gain, original recording, cancellation, offline
model, exact-word alignment and source provenance are baseline and do not count
as new additions. Tests, libraries, numerical thresholds and logging alone do
not count as user features either. No separate recitation/history screen.

19October retention update: the user removed recordings permanently. Original
PCM is now working data for the open Mushaf only, deleted on finish/close; the
old recording library and scope picker are removed. This supersedes historical
archive/relaunch requirements, without changing actual acoustic evidence gates.

`P` = planned, `E` = experiment, `I` = integrated but not fully verified,
`V` = implemented with the stated verification. Production/learner acceptance
must still be reported separately. Never infer V from a checked box or a model
publisher's benchmark. Evaluation uses unprompted acoustic hypotheses;
professional forced alignment must never adjudicate a learner.

| ID | Additional behavior | Required acceptance | State |
|---|---|---|---|
| 01 | Independent Quran CTC recognition opinion | Actual bundled FP32 prefix/whole recognition passed in native run ed44bf0; natural learner/device accuracy not established | V |
| 02 | Agreement from two independent recognizers | Native source-hash/clock and unique occurrence regressions passed; actual continuous public PCM passed; learner accuracy not established | V |
| 03 | Suppress correction when recognizers disagree | Native independent-only/gap and raw-source preservation regressions passed; no calibrated learner correction precision claim | V |
| 04 | Retry a low-confidence word with its genuine audio context | Bounded retry, original clock and original rejected hypothesis retained | P |
| 05 | Stable partial-word display | Retained shown ayahs plus source-clock navigation frontier integrated; withdrawn words lose active highlighting, older overlap cannot move page backward. Four new location regressions/native integration pending; natural learner acceptance remains pending | I |
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
| 16 | Recognize spoken opening letters | Position-bound complete names added; actual recognizer and long openings still under evaluation, display Quran bytes unchanged | I |
| 17 | Distinguish an introduction from Quran progress | Istiadhah/control clips produce no false Quran confirmation | P |
| 18 | Handle opening basmalah without wrong-surah jump | Ambiguous basmalah abstains without distinctive continuation | P |
| 19 | Detect clipping bursts separately from sustained overload | Actual normalized PCM and no false error grading | P |
| 20 | Detect a sustained DC offset in microphone input | Original PCM unchanged; bounded signal diagnostics | I |
| 21 | Remove measured DC offset from inference copy | Unchanged frame clock and real-audio recognition comparison | I |
| 22 | Detect disconnected/frozen microphone samples | Deterministic flatline evidence, not silence guessed as failure | I |
| 23 | Identify intermittent audio dropouts | Device sample/host clock discontinuity stops before concatenation, no generated silence; hardware acceptance remains pending | I |
| 24 | Avoid gain pumping from brief loud transients | Quiet speech+click controls; no clipping or timing shifts | P |
| 25 | Distinguish usable quiet speech from stationary noise | Real speech/noise held-out diagnostic and abstention | P |
| 26 | Cancel persistent signal advice after recovery | Hysteresis; brief healthy block cannot hide repeated fault | I |
| 27 | Maintain signal guidance across overlapping decode windows | Count capture time once, not duplicated ASR windows | P |
| 28 | Detect out-of-range PCM before recognition | Invalid amplitude never becomes accepted word evidence | I |
| 29 | Handle a bounded long held vowel without duplicate words | Genuine sustained speech, no duration-based correctness claim | P |
| 30 | Support slower recitation without losing the current position | Real slow recordings, bounded context/memory | P |
| 31 | Support faster recitation without dropping leading words | Real fast recordings and explicit overload behavior | P |
| 32 | Pause location uncertainty without resetting listening | Same inline UI, preserved genuine source evidence | P |
| 33 | Show a concise reason for tracking uncertainty | Distinguish no speech, unresolved words and unlocated passage; model disagreement remains pending | I |
| 34 | Show pending recognition separately from captured input | Actual capture/worker state; no decorative success pulse | I |
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

Twelve additional behaviors are integrated above; selected native verification
is recorded below. Existing per-take guidance reset/inline placement is preserved and is
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

Native run`6ad4e1467550aed8108fdbed`on`c0060b9`completed41selectedRelease
cases with2failures/exit65. Both failing remote-clock/source policy fixtures
used constant positive0.06PCM, now correctly removed as DC. Their assertions
are preserved; the fixture is now a balanced800Hz synthetic gate signal, and
a separate regression requires DCflatline to preserve raw observations while
revealing no words. No synthetic gate signal is acoustic acceptance. The other
39cases passed, including actualDC-fault reference audio. The corrected source
and new delayed inline worker/uncertainty feedback passed the matching native
run on`cea234c71f2f95801c979f12e0482961f4927ac2`, build
`6ad4e5bb7550aed8108fdd11`:43selected account-enabled Release cases,
0failures/testExit0,35.352seconds of test execution; total11m33s.
Xcode26.3/iOS26.2/iPhone17ProSimulator. The previous failure remains a
failure; its unchanged assertions now pass with genuine balanced policy input.
No fullRelease/physicalmicrophone/learner/Tajweed acceptance is implied.

The next unverified capture repair now reads the actual AVAudioTime supplied by
the device tap. A missing, duplicate, reordered or rate-changed sample interval
cannot be concatenated into a continuous take. Host-only timestamps are supported
without using callback arrival time; missing stamps stop explicitly instead of
guessing. Previous PCM remains saved and explicit resume starts a fresh take.
Matching native run`6ad4eb2e7550aed8108fde80`on
`18e7ac8d2f11ab26914f8db43668418da4b55cdc`passed49selectedReleasecases,
0failures/testExit0 in27.128seconds, total10m28s. The device-clock and input
lifecycle policies passed; this is not a real hardware dropout test. The newer
initials changes below were not part of that run.

`spoken-initials1` adds complete spoken letter-name aliases to the30initial
groups at their exact positions in29surahs, including42:2. It accepts only
ordered complete names, with alternative boundaries for recognizers that join
adjacent names. Ordinaryألم and noninitial positions are unchanged. Incomplete,
reordered or shared openings cannot choose a surah; the existing independent
anchor/uncertainty rules remain. Canonical text, native IDs and glyphs are not
rewritten, and raw observed words remain original. This lexical behavior is
integrated in native and server binding; real long-initial recognition and
phonetic correctness are not established. Matching native source3e961fcpassed53selected Release tests,0failures;
the earlier18e7ac8run did not include these changes.

Actual publicCPU eight-second-window diagnostics exposed a stronger failure:
on a short prefix the finetuned decoder sometimes emits a whole compact
opening with near1confidence and unrelated words. The full raw outputs are
retained in`outputs/public-initials-evaluation/actual-windows.json`, not relabeled
as correct. Therefore isolated-initial scopes are excluded from the general
single-word confidence waiver. They require following independent context;
neither a complete printed abbreviation nor a spoken-name alias alone proves
completion. This is conservative wording/location behavior, not verified
duration/pronunciation grading. Historical journal evidence is not claimed
to have been acoustically reviewed by this change.

The new negative native reference fixture is exact public AbdulBasitMurattal
2:1 from`https://everyayah.com/data/Abdul_Basit_Murattal_64kbps/002001.mp3`,
63319bytes/SHA256`48077d6641b2403e04c15585b0ede3b8eb3a3c354ae4d8d6f6a4882dc8106ebb`.
It is test-bundle-only and was not altered/spliced. No new private audio is
uploaded or used as ground truth. The actual public-prefix negative test was included in the matching53-case native pass.

Primary lexical references (reading names, not a pronunciation grading model):
[Alif Lam Mim](https://qul.tarteel.ai/morphology/word?location=2%3A1%3A1),
[Kaf Ha Ya Ayn Sad](https://corpus.quran.com/wordmorphology.jsp?location=%2819%3A1%3A1%29),
[Ta Ha](https://corpus.quran.com/wordbyword.jsp?chapter=20),
[Ya Sin](https://corpus.quran.com/wordmorphology.jsp?location=%2836%3A1%3A1%29).
Device-time API reference:
[Apple AVAudioTime](https://developer.apple.com/documentation/avfaudio/avaudiotime).

Independent raw CTC diagnostics on the same exact public prefix/full bytes
confirmed a separate hypothesis:2:1prefix `ال` versus full `الم`, and
19:1prefix `ك` versus full `كهيعص`. Eight bounded cases completed without
reference prompts or forced alignment; raw results are retained in
`outputs/public-initials-evaluation/independent-ctc.json`. This diagnostic
is not an integrated phone verifier or measured natural-learner accuracy.

## Latest learner request: keep a shown ayah visible

The user specifically requested that a recited Fatiha ayah stay visible while
reading the next. Completed-ayah display history is now separate from revisable
word evidence: after every native word of an ayah has been shown from evidence,
the complete ayah remains on screen even if a later overlapping ASR window
retracts the earlier interpretation. This never reveals an unread next ayah,
creates acoustic evidence, awards mastery or suppresses an uncertainty report.
When retracted text remains visible, later attempts record that assistance.
The display history survives pause/relaunch and stale analysis writes, resets
for a new session, and uses the existing Mushaf with no additional screen.

Implementation and matching native execution passed on3e961fc. Added native
policies reproduce Fatiha1:2 followed by a retracting window, confirm1:3stays
hidden, reopen the real saved PCM/journal, and verify both write orders preserve
visibility while allowing evidence retraction. These use injected recognized
words over original public PCM; they are display/persistence tests, not ASR
accuracy or physical microphone acceptance. Matching Codemagic build
6ad4f12b7550aed8108fe005passed53selected account-enabled Release tests with
0failures/testExit0 in33.176seconds; total10m16s, Xcode26.3/iOS26.2/iPhone17Pro.
Proof: outputs/engine-3e9-visible-ayah-passed.txt. This is not full Release,
physical microphone or all-reader acceptance.

## Visual acceptance queued after engine and readers

The user explicitly requested a visually balanced, centered Mushaf with
comfortable reading and Tajweed colors before publication. Preserve the
approved edition's Quran bytes, glyphs, authored line distribution and complete
page visibility. Compare real iPhone Simulator captures with tools shown/hidden,
regular/Tajweed modes, opening and dense pages, light/dark, small/large screens.
Do not substitute an HTML mockup for native visual evidence. This is a separate
product requirement and is not counted as extra engine features.

## Initial independent native integration (historical state)

Source2e96410bundles independent CTC for actual microphone windows. Original
PCM hash and capture-frame clock bind the two acoustic opinions. Only a unique
matching contemporaneous occurrence may retain a primary word; primary or
secondary gaps split the run. No reference text enters CTC. Disagreement and
verifier failure withhold progress while original PCM and hypotheses survive.

Actual Mac source36afe9aconversion matched raw words26/26, including the
public first-two-second openings and empty generated negative controls. This
was conversion parity, not accuracy: minimum frame-label agreement0.99537,
maximum posterior difference0.9937. Earlierint8candidate changed a public
prefix and failed its gate; it was not promoted. The float16 source graph and
weight bytes are pinned before Apple compilation. No model runtime download.

Local decoder/package policies:7passed. Current paired native integration
has not compiled/run yet; do not attribute3e961fc53/0to it. Full Release,
physical microphone, natural learner correction precision and Tajweed quality
remain unverified. No new TestFlight upload.

Professional timing: a bounded5GB localGPU allocator completed40records for
surahs94/97withoutbackenderrors:29candidates,9rejected,2resource-limited.
These remain unreviewed and unshipped. The separate all114/all20pass stopped
at a local disk reserve; most catalog rows were not actually fetched. Its
historical/partial receipts never constitute whole-library approval.

## Subsequent source and precision gates

The first native integration attempt on2e96410failed before compilation: the
regenerated CoreML graph differed from its pinned source. No native test ran.
Deterministic protobuf encoding and a fixed process hash seed were then added;
the next actual float16 trial on14ac32apassed25/26raw-word cases and failed the
first2seconds of public Fatiha1:2 (`لن` became `لل`). This failure is retained.
The previous36afe9a26/26result does not override a later failed precision gate.
No compressed candidate was released. Fullfloat32source5b63f27passed all26
actual raw-word comparisons and separate-process source-byte reproducibility
in Codemagic6ad505db7550aed8108fe58a(5m23s). The exact canonical graph SHA is
`a03be761fad1c1da230d0c3522ae3be7e20523147603d219751ad2abaaced5d7`;
converted weights SHA is
`bb4a2ffd5eb4082d8383c721887294886594ba77ec0d4611b38ea1796e231833`.
These actual pins now replace the failed float16 app-generation candidate.
Native compilation/integration tests, phone memory/latency and natural learner
quality remain unverified. No new TestFlight upload follows from conversion
parity alone. Proofs: outputs/coreml-5b6-actual-receipt.json and
outputs/coreml-5b6-reproducibility.json.

Streaming exact publisher windows and shrinking unused GPU arena allocations
after each inference completed both full Baqara source decodes without an
allocator exception. Exact source5b63f27receipts have286ayah results each:
Sudais54:258candidates/16acoustic rejections/12over45second resource limits;
Shuraym31:270candidates/5rejections/11resource limits. None is a whole-recording
pass. Negative controls rejected, and these candidates remain unreviewed and
unshipped. The actual MP3 hashes and per-ayah source frame intervals are kept
in outputs/reciter-streamed-long-real-20261018/report.json.

A resumed missing-negative-control run now recovers only a bounded actual
prefix, verifies newly fetched source bytes against the old recording receipt,
and remeasures if the bytes changed. The prefix is never a complete-recording
acceptance sample. The local tooling/package suite passed34cases plus9subtests,
including exact public-PCM decoder/prefix parity. These tests do not establish
learner or professional timing accuracy.

## Current native verification — ed44bf0

Codemagic `6ad50d777550aed8108fe77d` on exact source
`ed44bf01da9d7732d146de7030e8be649dbe64b5` completed 59 selected Release
tests with zero failures in 70.450 seconds, Xcode26.3/iOS26.2/iPhone17Pro.
This includes actual bundled full-precision CTC on a public first-two-second
prefix and its full clip, source identity/occurrence agreement policies, and
the real controller locating112:1 then114:1 within the same listening take.
The controller's transport supplies original public PCM; this is not a
physical microphone test. The two recognition checkpoints took16.772seconds
and5.735seconds respectively, including current preparation/processing.
They are not calibrated per-word latency measurements on a phone.

The earlier27d7069native run passed58/59, failing its first112:1checkpoint.
That failure remains recorded. Independent and primary model preparation
previously ran serially; ed44bf0warms them concurrently and retains the same
20second checkpoint condition. This matching rerun passed. Preparation of
the independent model measured10.952seconds in this run. No inference
precision, matching criterion or original PCM was changed to obtain the pass.

Proof: `outputs/native-ed4-confirmed-pass.txt`. Subsequent commits dd8d481
and2e1138cchange CI screenshot collection only; the `ios/` application tree
is identical to the passed source. Current native UI screenshot collection is
separate and pending. A previous UI workflow completed47unit cases including
all604Tajweed/hidden-word geometry and one UI journey, but timed out during
an additional comfort test; do not relabel that workflow as successful.

This verifies the limited scope of ledger01–03, not all50additions, natural
learner correction precision, calibrated Tajweed assessment, phone audio,
complete app Release acceptance, or word tracking for all20readers. No new
TestFlight upload has occurred yet.
