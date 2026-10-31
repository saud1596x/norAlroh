# Noor Alruh

Continue the existing native iOS application. The current owner contract and
source-bound acceptance state are indexed in `docs/release-acceptance.json`.
Preserve Quran text/edition, app identity, user data and uncommitted work.

Use the relevant repo-local skill before its domain change:

- `.agents/skills/noor-quran-geometry/` for Quran layout/touch/turning.
- `.agents/skills/noor-recitation-streaming/` for capture/windows/session work.
- `.agents/skills/noor-recitation-evaluation/` for recognition/accuracy claims.
- `.agents/skills/noor-widgets-notification-contracts/` for timelines/reminders.
- `.agents/skills/noor-release-evidence/` before closing a gate or delivery.

Current project declares Swift language mode5 and iOS17 deployment. Inspect
actual CI Xcode/SDK before adopting APIs from installed general Swift skills;
do not raise these settings merely to match a skill example. Native rendering
requires UIKit/Core Text. Windows has no iOS Simulator or Swift compiler.

Use permitted macOS CI for real Release/native tests. Retain pipefail and exact
test/producer/artifact identity. Do not equate helper tests with app behavior,
generated visuals with app screenshots or typed words with live recognition.

Keep one central acceptance/resume ledger, exact evidence links and honest
limits. Independent scoped agent work is authorized; one primary integrator
reviews changes and source-bound tests. No new paid service or account access
is implied. Current owner authorizes public delivery only after blocking gates.
