---
name: noor-experience-design
description: Design and evaluate Noor Alruh reading, return navigation, daily practices, and responsive night motion. Use for product redesign, interaction prototypes, or app shell changes.
---

Start with one complete journey. State what the reader is trying to do, the state they start in, and where they return. Compare the current journey with at least two interaction alternatives before choosing a layout. A new palette or particle effect alone is not a new journey.

Read [the design study](references/design-study.md) for current code evidence, proposals and review criteria. Carry the user's approved scope into implementation. Use noor-quran-geometry for the page and noor-reciter-timing for audio following. Keep the Quran resource identity and current platform targets.

Separate presentation clock, prayer clock and reading position. Ambient graphics can derive coordinates from one clock, but must not publish that clock through the reader, notification scheduler or root view. Pause when hidden, backgrounded or in the Mushaf. Respect system Reduce Motion and provide readable static states. Put interactive controls in semantic SwiftUI views outside the decorative Canvas.

For approvals, demonstrate a complete journey with a restart, a cancel or back action and a narrow screen. Distinguish working interactions from placeholders and browser prototype checks from iPhone tests. Score proposed changes on effort to resume, ability to return without losing place, offline behavior, and legibility. A prototype approval does not certify reading geometry or motion performance.
