# Additional voice diagnostic

The user requested both professional voices and authorized learner voices.
The local pilot uses12public source-recording groups from the publisher's MIT
dataset declaration at https://huggingface.co/datasets/sobolev210/quran-recitation-errors,
revision d196cd3132c69cd361d28cf6a8b442ae4e0bf0b4. Selection was frozen before
decoding: first12distinct reviewed Hafs recording groups sorted by SHA256 of
source path. Audio bytes are pinned in the local manifest; no audio or source
participant/reviewer identifiers are committed or uploaded by this pilot.

The publisher's license is not independent documentation of individual
participant consent. Voices are not yet qualified as a consent-verified
training/production corpus. Source recording groups are not verified speaker
identities, and model training overlap is unknown. TLOG and the Quranic ASR
benchmark remain gated; no alternate route was used to fetch them. RetaSy's
public card did not establish an explicit license, so its audio was not used.

Actual local CPU inference completed71unprompted rolling windows over all12
clips, preserving the full original timeline, including the29.968s clip. Initial
window2s, stride1s, rolling maximum8s, final partial window kept. Median primary
inference time1.547s on this host, excluding model initialization and iPhone
capture/UI. Source/backend is the pinned faster-whisper/int8 CPU2 model; this
does not measure WhisperKit or CoreML on an iPhone.

The existing pinned independent CTC model was also run on the same original
final window of each clip, with its input hash checked against the primary
report. CPU/dynamic-int8 backend, not CoreML numerical-parity evidence.
Of68primary accepted final-window word occurrences,54had a unique lexical
match with overlapping source time in the independent output. This is an
agreement count, not54correct words or an accuracy percentage. Original
hypotheses, disagreements, clocks and uncertainty remain in the local reports.

Intended Quran text and coarse publisher error categories were attached only
after decoding. They are not verified verbatim spoken transcripts or exact
error timings. No WER, correction precision, Tajweed accuracy, held-out speaker
generalization, training result or superiority over Tarteel is claimed.

Developer evidence (outside the repository):
outputs/learner-dataset-audit/pilot-manifest.json,
actual-pilot-report.json, actual-ctc-pilot-report.json and pilot-summary.json.
The CLI server/recitation/evaluate_learner_pilot.py repeats the bounded primary
diagnostic against the separately held manifest/model, without network calls.

The earlier complete local TCP/WebSocket run on22public reference/quiet/control
cases is a different diagnostic: outputs/beta-actual-loopback-complete/report.json.
It measured WER0.090909 and verse-detection rate0.4 on those short clips, with
22identical replay results. Shared short phrases intentionally abstain from
full-Quran location. These numbers are neither natural learner accuracy nor a
release pass. The interrupted earlier measurement remains incomplete.

Professional-reciter review now has75timing candidates across1/112/113/114,
out of2280required whole recordings. Source-specific acoustic/human approval
and the remaining long chapters are incomplete. Nothing from this candidate
review was promoted into the shipping timing library.
