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
