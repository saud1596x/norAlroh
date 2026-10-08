# Native Quran recognition investigation

Run `bash scripts/test-recitation-engine.sh` on a Mac. This small executable
uses the pinned Argmax WhisperKit API and a pinned Quran-specific Core ML
conversion, with actual word timestamps enabled. It does not rebuild, link
into or change the shipping iOS app. Downloads are public model data, verified
reference audio and an independently pinned OpenAI tokenizer. Exact downloaded
file hashes are exported with the decoding report.

The test material is ten professional recitation clips, explicitly assembled
repeat/return sequences, silence and deterministic low-level noise. Eight-second
overlapping windows are evaluated for the assembled sequences. The report
retains actual output, token confidence, segment speech probability, audio
offset and elapsed inference time. Nothing reveals words by a timer and nothing
turns an ASR mismatch into a confirmed reader error.

Successful execution checks model compatibility and usable finite timings.
It does **not** certify accuracy, microphone capture, iPhone performance,
pronunciation or Tajweed. Inspect hallucinations, omitted repeated phrases and
partial-word mistakes before selecting thresholds or connecting this engine
to a user's reading position. Live-device, independent-reader evaluation and
canonical word identity validation remain acceptance gates.

Model: `fazalshaikh123/ultra-fast-tarteel-coreml`, revision
`0338074ac8d662f6f52c5d66b433cac74202158e`. Runtime: official
`argmaxinc/argmax-oss-swift`, revision
`1e2a163736dfa5a198e637ae44c114e1c6d5cc2d`. See each source's original license
before distributing model assets; this probe does not bundle them in the app.
