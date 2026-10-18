# Offline professional-reciter alignment

This tool derives playback candidates from the **exact professional recording**.
It is never used to judge a learner or award recitation progress. It does not
interpolate unknown words. Rejected alignment remains unavailable.

The current candidate evaluator uses
[rabah2026/wav2vec2-large-xlsr-53-arabic-quran](https://huggingface.co/rabah2026/wav2vec2-large-xlsr-53-arabic-quran),
revision `b539d5fa66deb820c8e4762171ecb284ace4b52d`, publisher-declared Apache-2.0.
The weights/config/vocabulary are pinned in code; an editable download receipt
cannot authorize different model files. Built-in Transformers class,
safetensors and local-files-only loading; no remote Python code.
Arabic letter variants are marginalized into the same posterior, while vowel
and ornament labels go to blank. Every canonical native word still needs actual
acoustic evidence. No learner recording is processed by this tool.

The earlier alternative [parseh/aligner-ar](https://huggingface.co/parseh/aligner-ar),
revision `088bb8afed49b11e2a29a7a9b947b479e9ef3eaa`, Apache-2.0,
is retained for comparison, not selected for production. It rejected all20
Fatiha recordings with the free-edge policy. Keep model LICENSE/NOTICE with any
redistributed weights. Weights remain local tooling, not an app download.

The posterior/CER filters are engineering rejection rules; they are not
calibrated acoustic accuracy. No candidate is automatically promoted to the
production timing resource. Recording hash, native word IDs, silence/noise/
wrong-text controls, complete-surah coverage and acoustic review are required.

`run_library.py --model MODEL_DIRECTORY --output OUTPUT_DIRECTORY --max-minutes 10 --surahs 1,112,113,114`
performs a bounded, resumable pass. It retains one
temporary public audio file at a time and reserves1GB free disk. No microphone
audio, app credentials, model download or paid infrastructure is involved.
Python dependencies are NumPy, PyAV/faster-whisper for decoding and PyTorch /
Transformers for local Quran CTC inference. The existing CPU runtime was used.

Actual local pass on2026-10-18:80 exact catalog recordings across four surahs,
69 whole-recording candidates and11 rejected. Candidate native-ID sequences
were checked against the pinned Mushaf snapshot; silence/noise/wrong-text
controls rejected for each surah. Seven algorithm/pinning tests passed. These
are neither human acoustic review nor app playback acceptance. Full2280-track
coverage, weak-word repair, long-surah/isolated-letter evaluation, candidate
review and runtime resource integration remain incomplete.

The bounded runner now fingerprints the alignment code, exact reader catalog,
published ayah data and canonical edition before resuming. Every ayah is
checkpointed; a time limit is not a rejected word or a completed recording.
Missing/duplicate/overlapping/out-of-duration ayah windows reject the track.
Reports are written atomically, public audio is fetched one file at a time, and
each subsequent fetch/ayah checks the local deadline. A single running model
call can still finish after that deadline; the next call cannot start.
`full-library-coverage.json` enumerates all2280 expected recordings, including
missing tracks. Old-policy candidates remain distinct from current-policy
results. Neither a candidate nor a passed silence control is acoustic approval.

## Optional local CUDA experiment

`export_onnx.py` exports the pinned local weights with an explicit precision and
oneGBdisk reserve. The evaluated FP16export has a code-pinned SHA256; an editable
receipt cannot replace it. `evaluate_onnx.py` compared22actual public/control
cases to original non-quantized FP32CPU output: same greedy word strings,
including empty silence/noise controls, but maximum frame posterior difference
0.2568. Actual execution profiling confirms CUDA nodes; the31mswarmmedian on a
localRTX5060 is not iPhone/cloud speed or improved learner accuracy. Cold
inference/shape planning was slow and emitted cuDNN warnings. No model is shipped.

Pass`--onnx ONNX_DIRECTORY`to`run_library.py`for the bounded CUDA candidate
audit. Code/precision/runtime/export hashes are part of resume identity;
CPUcheckpoints cannot silently become GPUproof. A30second inference interval
limit is recorded as`RESOURCE_LIMIT_NOT_ASSESSED`, never acoustic rejection.
On a short known professional recording, an invalid/rejected publisher ayah
clock may be replaced only by a complete independent whole-recording CTC path,
using exactly the same acoustic thresholds and native-ID/duration checks. The
failed publisher proposal remains in the receipt. No clamped clock, interpolated
word or learner-reference forcing. Candidates remain unavailable in the app
until separately reviewed and integrated.
