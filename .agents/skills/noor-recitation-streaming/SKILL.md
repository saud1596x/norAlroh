---
name: noor-recitation-streaming
description: Trace and repair Noor's microphone, PCM conversion, bounded windows, inference scheduling and session cancellation without fabricating recognized Quran.
---

Read REC acceptance items and preserve existing user drafts before editing capture/controller/worker code.

- Trace actual input format → conversion/sample offsets → window mailbox → model preparation → independent decodes → location/alignment → durable decision → Quran overlay. Record separate capture, model-ready and position-confirmed states.
- Keep audio callbacks free of inference, filesystem work and unbounded UI tasks. Meter telemetry may coalesce; PCM coverage may not silently drop. A 10,001-event meter regression must not grant frames or reading evidence.
- Preserve the held unprocessed prefix during cold preparation. Extend only with byte-identical, contiguous real overlap and the bounded window size; retain unconsumed tail. Gaps or changed overlap bytes are failures, not a new contiguous window.
- Cancel and finish each task/stream at pause, stop, failed start and replacement. A stale session/take must not publish into its successor.
- Use the real PCM sample clock for elapsed recording. Wall-clock movement or quiet Simulator capture is not recognition evidence.
- When using the installed `coreml` skill, preserve Noor's pinned FP32/CPU-only model and source bytes, lexical/frame gates and existing worker ownership. Generic `.all`/Float16 performance advice does not override measured Noor results. Separate actual hash/load, input preparation, prediction and postdecode timings; do not move synchronous prediction to MainActor or replace single-flight preparation with the reference's generic cache/background unload examples. Keep Swift5/iOS17; guard MLComputePlan at iOS17.4 and MLTensor/MLState at iOS18 rather than migrating the SDK or language mode.
- For the heard header and single start/finish microphone control, apply `ios-accessibility` semantic Arabic labels/state, Dynamic Type, RTL and 44-point targets. Apply `swiftui-animation` only to short, scoped feedback driven by actual state; respect system/app Reduce Motion and finish/disappear/background cleanup. Do not animate Quran text/word positions, synthesize meter/recognition progress, or add unbounded loops/dependencies. Source review, UI fixture captures and XCTest metadata remain separate from actual microphone/ASR and assistive-technology proof.
- Run the medium `recitation-contracts` native lane and inspect source-specific counts, including microphone lifecycle, mailbox, live storage and worker lifecycle. No Swift/Xcode is present on this Windows host.

**Examples:** the integrated cold-prefix test uses the bundled permitted 001002.mp3 bytes through injected capture and a preparation barrier, with the recognizer returning no words. It proves scheduling/coverage, not microphone or ASR accuracy. Corrupted overlap and a genuine source gap must be rejected by mailbox regression fixtures.

**History:** 2026-10-31: captures the real cold-preparation and UI callback backlog findings. The model revisions and capability limitations remain in the product manifests and central REC ledger; this skill does not train a model.
