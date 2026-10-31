---
name: noor-recitation-evaluation
description: Evaluate changes to Noor ASR, alignment, location or error decisions using consented speaker-separated audio and raw source-bound results.
---

Use when changing a recognition model, decoding, thresholds, alignment or claiming better accuracy. Read REC-007/008 first.

1. Inspect the actual replay/evaluation scripts and manifests. Preserve raw audio-derived hypotheses separately from expected Quran and display text.
2. Require permitted recordings, manually reviewed transcript/error times and speaker/session identities. Split speakers and duplicate recordings across train/validation/test; never label a model transcript as ground truth.
3. Run the same production processing with actual chunking/timestamps, and separately full-file replay. Test silence/non-Quran, repetition, slow reading, self-correction, similar ayat, a different starting surah and boundary words.
4. Report raw/normalized WER policy, location/word accuracy, per-error precision/recall, false alerts per correct-reading minute, first/recovery/error latency, queue growth and device conditions. State the denominator and statistical limits.
5. Keep wording, tracking and acoustic Tajweed claims separate. The charter's 95% precision/90% recall and one false alert per20minutes are targets, not measured results.

**Positive case:** a permitted expert-reference replay can prove a specific file/model output and timing only. It cannot establish a held-out learner population.
**Negative case:** audio that differs from the opened ayah must not pass merely because the expected text was supplied; an expected-text-only recognizer must fail that experiment. Run isolated fixtures, never alter real user audio or production Quran to manufacture the case.

**History:** 2026-10-31: preserves the prior rejected FastConformer probe and the distinction between quiet capture, typed-word tracker fixtures and actual independent audio evidence. Missing consented learner ground truth remains an explicit external dependency.
