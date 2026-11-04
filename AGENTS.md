# Noor Alruh

Continue the existing native iOS application. The current owner contract and
source-bound acceptance state are indexed in `docs/release-acceptance.json`.
Preserve Quran text/edition, app identity, user data and uncommitted work.

Use the relevant repo-local skill before its domain change:

- `.agents/skills/noor-experience-design/` for product journeys, design prototypes, and app shell changes.
- `.agents/skills/noor-quran-geometry/` for Quran layout/touch/turning.
- `.agents/skills/noor-reciter-timing/` for reciter playback, recording-bound word/ayah clocks and page following.
- `.agents/skills/noor-recitation-streaming/` for capture/windows/session work.
- `.agents/skills/noor-recitation-evaluation/` for recognition/accuracy claims.
- `.agents/skills/noor-widgets-notification-contracts/` for timelines/reminders.
- `.agents/skills/noor-release-evidence/` before closing a gate or delivery.

Current project declares Swift language mode5 and iOS17 deployment. Inspect
actual CI Xcode/SDK before adopting APIs from installed general Swift skills;
do not raise these settings merely to match a skill example. Native rendering
requires UIKit/Core Text. Windows has no iOS Simulator or Swift compiler.

Use the pinned `coreml`, `ios-accessibility`, and `swiftui-animation` skills for
their specific domains. Their sources and all installed-file hashes are recorded
in `.agents/skills/skill-sources.json`; their PolyForm Perimeter licenses and
required notices must remain with the installed material. They are developer
instructions, not models, runtime dependencies, or native acceptance evidence.

- Core ML: preserve the current FP32 model/source hashes, CPU-only configuration,
  PCM/frame contracts and accuracy gates. Noor's measured CPU/ALL results override
  generic claims that `.all` is fastest. Measure real cold/warm load, preprocessing,
  prediction and postdecode separately. Keep synchronous inference off MainActor
  in the existing worker and preserve single-flight preparation/cancellation.
  Do not copy generic cache, background unload, Float16 or compression recipes.
  Gate `MLComputePlan` at iOS17.4 and `MLTensor`/`MLState` at iOS18; no Swift6.4,
  SDK27 or deployment migration is authorized by a skill example.
- Design/accessibility: use semantic controls, meaningful Arabic labels/states,
  at least 44-point targets, Dynamic Type, RTL, contrast and sensible traversal.
  Check the heard header and single microphone control in each actual state.
  Source/XCTest checks do not replace native readability or assistive-technology
  evidence. Guard the skill's iOS18 Assistive Access examples.
- Motion: use short, scoped, value-driven feedback from actual UI/audio state.
  Respect system/app Reduce Motion, interruption and finish/disappear/background
  cleanup. Do not add unbounded loops, dependencies, fake recognition progress,
  or animation of Quran text, word positions or evidence geometry. Native iOS17
  phase/keyframe APIs suffice where needed; newer effects require availability
  checks. Do not add display links, forced frame rates or compositing workarounds
  without a measured need.

Use permitted macOS CI for real Release/native tests. Retain pipefail and exact
test/producer/artifact identity. Do not equate helper tests with app behavior,
generated visuals with app screenshots or typed words with live recognition.

Keep one central acceptance/resume ledger, exact evidence links and honest
limits. Independent scoped agent work is authorized; one primary integrator
reviews changes and source-bound tests. No new paid service or account access
is implied. Current owner authorizes public delivery only after blocking gates.
