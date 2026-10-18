# Build 24: device-reported regressions

The user installed 1.0 (24) and reports that the main microphone does nothing,
while verse-menu recitation works, recognition is worse, page turns hang, and
opening the installed Mushaf shows preparation. Prior 59 selected native tests
and 3 UI tests did not establish these physical-device behaviors. This report
supersedes any assumption of successful device acceptance.

## Concrete differences and repairs awaiting native verification

- Main microphone used a custom exclusive long-press/tap PrimitiveButtonStyle
  and an audible completion gate. An absent completion canceled capture and its
  error was outside the idle dock. Verse actions bypassed both. The main button
  now uses native Button activation, the existing normal press appearance, and
  immediate haptic-only capture. Resume uses the same non-audible path. Options
  remain in their explicit button; no new recitation screen is introduced.
- Opening ordinary reading eagerly loaded Whisper and the large independent
  CTC verifier. Reading now prepares scripture only; acoustic loading follows
  explicit capture intent. Home-screen preparation shares the same validated
  scripture actor and verifies the last page font before navigation where time
  allows. This cannot guarantee zero cold-start time on every device.
- The complete pinned bundled edition previously triggered a network refresh,
  re-decoding and writable cache work. Bundled reading now stays on its verified
  in-memory installed edition. Explicit cache refresh functionality for callers
  without installed content is preserved. Quran text and authored rows did not
  change.
- Font disk reads, manifest parsing and SHA256 inherited MainActor for current
  and neighbor fonts. These now execute on a detached worker; registration and
  observable state remain on MainActor. Verified immutable bundle font names
  can be reused by subsequent reader instances.
- A manual page number changed before its font was ready, removing the UIKit
  viewport for a spinner. Manual turns now keep the old page mounted until the
  requested font is ready; obsolete/closed-reader turn requests cannot commit.
- Independent acoustic inference ran only after primary inference. It now
  starts on the same original PCM in parallel, with the existing exact-word,
  occurrence, timing and dual-source acceptance conditions unchanged. Actual
  iPhone latency, resource usage and natural-reader accuracy still need evidence.

## Verification plan

`device-reported-reader-repair-check` is bounded to 18 minutes. It retains the
prior actual public-PCM/omission/silence/weak-signal/independent-model cases and
adds cue bypass/cancellation tests, bundled offline reopening, viewport tests,
a real single tap through OS permission denial, and eight actual page swipes.
No simulated microphone audio, model output or Quran words are injected into
the UI test. Public PCM controller tests remain distinct from physical capture.

Local six Python release-channel/deadline checks and exact 6236-verse/112-basmala
source comparison passed. Tree-sitter found no syntax errors in the changed
Swift files; this is not Swift compilation. Native tests are NOT RUN on this
repair at the time of this note. No new TestFlight build has been started.

Full device acceptance, natural learner accuracy, full release suite and
recording-specific verified word timings for all 20 readers remain incomplete.
Do not describe this repair as full engine or all-reader completion.
