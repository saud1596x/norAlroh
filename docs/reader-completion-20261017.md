# Reader completion and actual evidence, 17 October 2026

The current changes retain the approved uncolored QCF V2 reader. Manual turns,
page-entry UI and an in-flight drag are blocked while the reader's playback
sequence owns the page, including buffering/pauses. Canonical audio callbacks
may still advance the page. Selecting another voice remains an explicit action;
it does not silently start playback.

## Actual recognition result

Codemagic `6ad3d1117550aed8108fa8fa`, source `afc95e8`, Release, Xcode26.3,
iOS26.2/iPhone17Pro simulator completed **41 unit cases with zero failures**.
This includes actual bundled-model recognition of public PCM from112:1 then114:1,
the full6236-verse binding, both journal write orders,13 viewport regressions,
all604 original V2 page renders and10 real reference clips through WebRTC VAD.
It does not establish phone microphone behavior or calibrated pronunciation,
error-detection or Tajweed accuracy.

The same run failed its one UI journey at the missing cancellation control in
an adaptive confirmation popover. `72c4535` replaces that popover with a scrolling
sheet and explicit close control. Further tools open only after sheet dismissal.
Do not label the failed UI run as a complete pass.

## Original Tajweed layer implementation

Fonts: official Quran Foundation QCF V4, page-specific TrueType COLR v0,
`https://verses.quran.foundation/fonts/quran/hafs/v4/colrv1/ttf/p{page}.ttf`.
The URL says colrv1; the downloaded actual fonts use COLR version0. Preparation
checks the actual table version, not the URL label. Pin the604 originals and
their extracted COLR/CPAL metadata. Never distribute a separate font archive.
Keep the provider credit in the terms/credits area, outside the privacy policy.

Paint the original glyph-layer paths using the font's actual light/dark CPAL
palette. No inferred character rules, word-level color approximation, palette
replacement, changed font outlines or phoneme assessment. Canonical IDs remain
the app's original native IDs. Whole-line Core Text shaping still determines
glyph advances and hit geometry; the COLR union determines the visible ink.

V4 advances differ from V2. Colored mode uses one fixed23-point edition size
on the same page grid, never per-line compression or stretched glyphs. A native
test must check all604 pages in both palettes, actual colored pixels, hidden-word
geometry, canonical hit regions, cached variants and restoring V2 when disabled.
Default is off; the saved toggle is in the visible reader options sheet.

Local binding audit:83665/83665 native glyph records match the QUL V4 script,
after removing ASCII separators and merging the three known source token splits
2:181:3,8:6:4,13:37:8. This preserves every PUA code and does not modify Quran text.
Source-copy integrity remains6236 verses and112 separate basmalas, exact Unicode.
Neither this comparison nor pixel tests replace specialist printed-page review.

The first colored-mode native attempt `6ad3d4857550aed8108fa9d2` failed correctly
at staging: the QUL font archive and official CDN differ on page4. No compilation
or tests ran. Review the actual CDN originals before updating any pins; do not
disable this integrity check. The new test is not yet a passing result.

The current CDN originals were fetched and pinned subsequently. A semantic
comparison with the older QUL zip found28 outline/advance changes and430 color
paint changes after resolving glyph renumbering; do not describe the two font
versions as identical. The app uses the current publisher files, without editing
font bytes. Specialist review of the colored edition remains unestablished.

Run `6ad3d6af7550aed8108faa5a` on `5fb132a` compiled the actual app and completed
42 unit cases plus one UI journey.41 unit cases and the UI journey passed;
the new colored-mode test failed80 assertions on20 pages. All20 failing native
word IDs contained an ASCII separator inside a compound. The renderer incorrectly
looked up the companion blank's glyph ID in the page font's COLR table, painting
an unrelated companion shape. Skip ink for these validated all-space runs while
retaining their shaped advances. Never change the Quran words or shrink an
individual word to hide this failure. The next run also paints all604 colored
pages in both themes and records actual swipe/selection/picker UI when possible.

## Remaining recording-specific coverage

All25 current recording identities are selectable in one searchable picker.
The existing published word timings cover only parts of three exact EveryAyah
recordings. They must not be attached to a similarly named MP3Quran or QUL file.
No timings are interpolated and listening never earns learner-recitation credit.

Actual QUL415 Juhani export has6236 ayah records and **zero word segments**,
despite its generic “With segments” tag. The flag alone is not word coverage.
QUL113 Maher and102 Sudais expose word segments, but point at different audio
recordings and need separate identity/binding/coverage and acoustic review.
Universal word following for all20 whole-surah Haramain recordings is therefore
still incomplete. Do not represent picker availability as word-timing completion.

## Distribution scope

Only the specifically authorized personal TestFlight channel may be used with
honest remaining limitations; do not alter normal preview/App Store gates or
claim full Release/device acceptance. New source must be pinned and its actual
checks recorded. All previous failed or unfinished results remain failed or
unfinished. No new invitation, credential or public App Store release.
