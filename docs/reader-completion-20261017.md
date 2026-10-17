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

Native source `8e6950e` / run `6ad3e0d07550aed8108fac8c` passed25 targeted
unit regressions, including the exact legacy preference/bookmark test (0.030s).
The tightened UI test exposed a genuine interaction defect: tapping the Toggle
left its value0, and the native canvas correctly continued reporting ordinary
reading. Two assertions failed; do not label that UI run successful or the image
colored. Replace the ambiguous List Toggle hit target with one explicit full-row
button (48pt minimum), visible enabled/disabled state and accessible value. The
follow-up must still tap the real action and prove the actual canvas changes to
colored mode and back; it must not set preferences or rendering state from tests.
The existing25-case and swipe/selection/hide/picker assertions remain intact.

Source `2a36ee7` / run `6ad3e3cd7550aed8108fad54` passed25 native unit
cases (10.889s) and1 actual UI case (76.735s), zero failures. The full-row color
action enabled the stored preference, the native canvas reported colored mode,
then returned to ordinary reading after disabling. Original `tajweed-reader-full-screen`
PNG SHA256 `0c659e110d407ba0bba47292be545ce14e5943554df137fa95dd504937525aba`
was reconstructed without alteration and visually inspected: actual publisher
colors, complete page604, three surah headings and visible spaced controls.
The other three original attachments show ordinary page604, clear yellow ayah
selection/actions and the last searched reciter selected. Actual UI movie exited0,
27,674,758bytes. This proves these UI actions on the simulator, not acoustic
error accuracy, real microphone performance or universal reciter word timing.

The private review inventory now pins490 tracked source files for this runtime.
Its unresolved flags remain unchanged. The older full42-unit run is retained as
component evidence; it was not rerun or attributed to this latest source. Normal
reviewed-preview/App Store evidence remains unchanged and is not a success claim.

## Follow-up: microphone and adjacent controls (18 October)

The user requested a calmer, attractive animated microphone and adjacent
visibility controls with tactile and audible tap feedback while the first
signed archive was running. Cancelled `6ad3e69e7550aed8108fae15` before upload;
it is not a delivered TestFlight build. Keep the existing publication request
and cost ceiling; verify the new UI before the replacement archive.

A compact shared dock uses quiet gold outlines, separate62pt utility targets,
a70pt microphone ring, short labels and a spring press response. Active input
ring motion follows only the controller's measured microphone meter; there is
no random waveform or claim of hearing while idle. Reduce Motion/low-motion
preferences disable scaling. Long press remains exclusively an options action.

The original60ms mono PCM earcon (`mic-start.wav`) is UI feedback only, never
recognition evidence or a substitute for public/user PCM. System Sound Services
honors the system's volume/silent behavior. Capture begins only after its real
completion callback plus100ms acoustic clearance. Creation failure starts
quietly; a queued sound timeout fails closed and offers a retry, never a fake
completion. Leaving/backgrounding cancels pending starts. Pause gives haptic
feedback without injecting an audible cue into the closing take; resume uses
the same pre-capture gate. The17 local payload/authorization tests pass, including
missing/corrupt UI sound rejection. The five new native ordering/asset tests use
a manual sound driver and must not be described as speaker/microphone tests.

Primary API: https://developer.apple.com/documentation/audiotoolbox/audio-services
Physical cue audibility, haptics and microphone isolation remain device testing;
no new acoustic accuracy or full-app acceptance claim is made.

Source `9a00d6d` / run `6ad3e9387550aed8108faeae` passed30 native cases
(13.182s) and1 UI case (83.330s), zero failures; terminal8m43s. All five new
cue ordering/asset cases passed. The UI also demonstrated the exclusive long
press, options close, actual colored mode on/off, real603/604 swipe, selection,
hiding and saved reciter choice. Original screenshot of the normal new dock
SHA256 `c09338ef5910c5bf6b4fe7a2aac5dc741c328eb510ce215d3410fcb27d580be0`
was visually inspected: complete page604, legible short labels, separated touch
areas and no footer overlap. The actual UI movie exited0,29,678,455bytes.

A subsequent small UI guard applies the controller's existing idle/stopped-only
start rule before queuing a decorative sound, at cue completion and in the
button's enabled state. This closes a repeat-tap window while `bind()` is awaiting
and `record` is still nil. The current native30-case pass belongs to9a00d6d;
this guard has not had a separate simulator run. Its exact source delta is
recorded in the private review inventory, and the replacement signed archive
must compile it. Do not relabel the earlier pass as testing this later guard.
No physical cue, haptic, microphone or acoustic-accuracy pass is claimed.

## Build23 upload and distribution follow-up

`e5cf935` / `6ad3ec3c7550aed8108faf62` compiled the small startup guard, signed
and exported the IPA, passed the complete payload checks (including the UI WAV,
26 recognition files,604 original Tajweed page resources and the four extensions),
and uploaded version1.0 build23 successfully. Delivery/build UUID:
`1505f1e1-f4a6-46b1-9993-6a0ace78b42d`;359,508,133bytes. Apple completed
processing after4m40s. This is not an installability confirmation by itself.

The remaining post-processing task failed at explicit association with the
existing internal group: `Cannot add internal group to a build`. The vendor's
maintainer discussion documents this exact error for automatic distribution
(https://github.com/orgs/codemagic-ci-cd/discussions/2488). This suggests existing
automatic access may already apply; account/phone confirmation is still required.
App Store Connect tab9 is logged out and the user was asked to sign in privately.
Do not claim build23 is installable before that confirmation.

Future private-review workflow repair removes explicit beta-group assignment
and sets `submit_to_testflight:false`. In the vendor CLI this option means
submitting for beta review, distinct from basic internal availability. See
https://github.com/codemagic-ci-cd/cli-tools/blob/master/src/codemagic/tools/app_store_connect/actions/publish_action.py
and the maintainer's discussion2536. No group membership/settings, credentials,
tester invitations or App Store publication are changed. This YAML-only repair
does not rebuild, expire or alter the already uploaded build23. Preserve the
actual post-processing failure and all unresolved accuracy/device flags.
