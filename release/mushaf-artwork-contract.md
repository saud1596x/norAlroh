# Fixed page renderer — source and acceptance record

## Current outcome

The attached references were actually opened: pages **1, 2, 3, 151 and 604**.
Page 604 was compared to the existing production iOS canvas. None of the
retrieved packages is accepted as a visually matching replacement. The new
renderer is implemented but **not activated**. No native Quran "after" image
exists yet. A geometry fixture containing ordinary rectangles is not Quran
artwork and must not be presented as an after image.

This change preserves the existing reader until an accepted complete package
exists, rejects malformed installed packages, and blocks the signed publishing
workflow while the acceptance receipt is unresolved. This is an incomplete
renderer migration, not a completed Ayah appearance match.

## Confirmed causes in the old implementation

`QCFV2PageLayout` infers headers from first-verse positions and assigns Amiri.
`MushafLineCanvas` joins glyph records with added spaces. `MushafTypesetter`
fits and justifies individual lines, and right-aligns short lines after fitting.
`MushafReader` sets row heights from viewport width and vertically scrolls.
The original ornamental frame, calligraphic basmala and title artwork are absent.
The Quran Foundation QCF V2 font/snapshot hashes establish internal integrity;
they do not identify the artwork build used in the supplied Ayah screenshots.

## Investigated sources (none adopted)

* KFGQPC master Hafs 1441H: individual PDF-compatible Illustrator pages 1, 2,
  3, 151 and 604 retrieved from the Quran.ws archive. Source package metadata
  names `1441-AI-hafs.zip`, SHA-256
  `280c5d71ca16aaeeb3a343be1b92c76fa6df71d0671e202c026fde12402d9eef`.
  **The full archive was not downloaded or independently hash verified.**
  Page 604 contains green printing placeholders, not the reference ornaments.
  Official source: https://dm.qurancomplex.gov.sa/.
  Archive metadata: https://github.com/quran-ws/kfgqpc-resources.
* https://github.com/batoulapps/quran-svg, revision
  `78d97544bfdc57e9f04bc97ace3f857ed972d772`: explicitly converted from the
  Complex's Illustrator files. Raw page 604 was rendered and examined. It has
  the same printing placeholders. Its optimized pipeline removes decorations.
* https://github.com/quran-ws/quran-svg: Hafs/KFGQPC 1441H. Page 604 was
  rendered and examined. Provenance explains removed decorations and redrawn
  ayah markers. The base body is close, but the reference identity is unproven.
* https://github.com/NedaaDevs/quran-image-generator: read source, not executed
  as a Quran source. Its author warns generated pages have not been proofread.
* `surah-header.ttf` from that project's `common.zip`: embedded name-table
  notice restricts publishing without permission and credits Freepik artwork.
  **Excluded from the app.** Merely locating a download does not establish rights.

The screenshots alone do not establish the exact edition/build or ownership
of the ornamental assets. Do not infer a precise edition year from font resemblance.

## Package contract

Supply `ios/Athar/mushaf-artwork-manifest.json` and 604 one-page transparent
PDFs named `mushaf-artwork-001.pdf` through `mushaf-artwork-604.pdf`.

The manifest contains `schema: 1`, exact `edition`, `sourceURL`, immutable
`sourceRevision`, a checked `rightsRecord`, `reviewStatus`,
`reviewedReferencePages`, and ordered `pages`. Each page has its original
`width`, `height`, `file`, SHA-256 and ordered `regions`. Each region has a stable
Tanzil-compatible `verseKey` (`surah:ayah`) and **separate** top-left-coordinate
polygons for every printed line occupied by that ayah.

All Quran paths, diacritics, surah headings, basmalas, frames and ayah medallions
must already exist in the source page. Neither screenshots nor OCR may create
them. PDF media/crop boxes have origin (0,0), equal dimensions, no rotation,
one page and transparent paper. Paths are tinted with the existing ink color;
the background remains `Theme.panel`. Original paths are never stretched.

The loader checks 604 ordered pages, all 6236 canonical verse keys in order
(including cross-page continuations), polygon bounds, page hashes and PDF
boxes before activation. This structural validation is **not** content approval.

## Rendering and interactions

`MushafPageTransform` uses `min(viewportWidth/pageWidth, viewportHeight/pageHeight)`.
Extra margins are retained. UIKit displays one vector page, with optional zoom
on that page; there is no default vertical scrolling. Tap toggles controls;
long press hit-tests the original polygons. Selection fills each polygon,
never the bounding box of a multiline ayah. VoiceOver reads the independent,
verified Tanzil text. Existing bookmarking/copy actions use canonical verse keys.
New listening and tafsir services are **not** implemented by this canvas change;
they require independent integration through the same verse-key callbacks.
Last page uses the existing persistent key. Tools use opacity and overlay
layout, so showing/hiding them does not reflow or rescale the page.

## Acceptance still required

1. Resolve the exact matching asset package and documented rights, including ornaments.
2. Verify all 604 source pages and same-package coordinates; do not mix editions.
3. Capture actual application output for 604 first, then 1, 2, 3, 151.
4. Crop the page regions and uniformly scale. Use
   `scripts/compare-mushaf-reference.py` for paper-color-independent overlays
   and edge-tolerant differences. Do not use nonuniform registration or
   per-line warping to conceal layout discrepancies.
5. Review letter paths, all marks, positions, short-line centers, line endings,
   basmala, headings, ornaments and margins separately. A single score or a
   passing build cannot approve these.
6. Bind the approval receipt to the manifest SHA-256 and actual native after
   evidence. Only then activate and pass `check-mushaf-publication.py`.

No approval status may be generated automatically from hashes or screenshots.
