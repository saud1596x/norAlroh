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

`8fb82e3` / run `6ad3d9767550aed8108faaef` completed **42 native unit cases with
zero failures**, including actual paint of all604 colored pages in both themes
(38.401s) and the real public-PCM cross-surah case (10.509s for the whole test,
not a per-word latency figure). The app's runtime remains unchanged after this
source. Its UI case completed selection, hiding and reader persistence but
failed two exact Arabic page-label comparisons. This run is still a failed run;
do not call it a complete pass or assume a gesture defect without the actual page.

The follow-up UI test retains the exact603/604 and604/604 assertions while parsing
actual numeric values across localized/invisible text formatting. It logs the
unmodified accessibility labels, does not change page state to force a pass, and
must still demonstrate a real swipe and Next action. The separate reader-ease
run checks this journey and24 existing regressions, not a new full42-case run.
Original screenshot attachments are exported through bounded, SHA256-verified
CI log chunks as well as private artifacts; the desktop artifact download
returned HTTP401 without authentication, and no API token was read to bypass it.

Additional confirmed preference bug: older64kbps Sudais/Shuraym directories
remained valid for cache/bookmark loading, but `NoorMushafReciter.selected` only
searched the modern25 entries and could not restore them. Preserve the exact
legacy recording and its cache namespace; do not silently choose AbdulBasit or
transfer192/128kbps word timing. The older choice appears in the picker only for
an existing saved preference. A new controller-level regression must verify
restoration, zero automatic playback and the exact112001 media URL. This small
catalog migration is not part of the earlier8fb native result until checked.

Reader-ease source `aecde4a` / run `6ad3dd8f7550aed8108fabca` passed24 unit
regressions and1 UI case (54.276s). Actual unmodified labels were
`الصفحة ⁨٦٠٣⁩ من ٦٠٤` and `الصفحة ⁨٦٠٤⁩ من ٦٠٤`: U+2068/U+2069 isolation around
the localized number caused the earlier literal comparison failures. No page
state was forced. The real swipe and Next returned the expected pages.

Four original PNG attachments were reconstructed with matching SHA256, and an
actual UI recording completed (exit0,33,538,873bytes). Visual review found that
the earliest screenshot had captured initial loading. Tighten readiness to the
visible, hittable completed viewport; also require the actual native canvas's
accessible rendered color mode and the Switch value before the colored-screen
capture. Do not label an early loader or an unconfirmed appearance as a verified
Tajweed UI screenshot. The next run includes this bridge and the new exact-reader
preference/bookmark namespace regression. Acoustic/color rendering itself is
unchanged from the successful42-case8fb run.

The private TestFlight workflow now targets the previously existing **Internal
Testers** group, confirmed in the app's saved Apple sidebar. Codemagic performs
post-processing through the existing integration; no new group, invitation,
credential, Apple browser login or public App Store submission is requested.

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
