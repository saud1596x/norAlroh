# Confirmed original King Fahd Mushaf

The user confirmed the displayed original page 604 from **KFGQPC المصحف العادي / standard39-2.pdf**. This supersedes the earlier request to reconstruct the Ayah screenshot's artwork. No claim is made that these two references are identical.

## Source and installation

Official source: https://qurancomplex.gov.sa/wp-content/uploads/isdarat/hafs/standard39-2.pdf

Hash-verified transport mirror: https://cdn.quran.ws/KFGQPC/resources/quran-hafs/standard39-2/standard39-2.pdf

SHA256: `5c4297de1fb6b654f641eed33242408d89432cbecf8a96ff5d297cb45fea7f07`; bytes: 243520529.

Run `python3 scripts/prepare-king-fahd-mushaf.py` before XcodeGen, or pass `--source` for an already downloaded exact original. The preparation script copies the full original unchanged. It refuses size or hash mismatches. The large reproducible PDF is not committed to Git.

The document has 640 physical leaves. Printed Quran pages 1–604 occupy physical leaves 4–607 (one-based). The runtime verifies hash, total leaves and all 604 media/crop boxes and rotations before activating it. The audit records all original image dimensions. This is structural verification, not a claim of human review of all 604 pages.

## Rendering

The canvas supplies a white paper base for the PDF’s unpainted outer margins. CGPDFPage draws the original publisher content including frames, surah titles, basmala and ayah markers. There is no font substitution, OCR, text regeneration, manual spacing or per-page exception. One uniform scale fits the complete original page. Reading tools reserve fixed margins, so showing/hiding tools does not reflow the page. Page number navigation, saved last page and zoom are implemented.

The source is raster artwork embedded in PDF, not vector lettering. Zoom cannot recover detail beyond the original raster resolution. Original colors are retained.

## Interaction boundaries

Tanzil Uthmani 1.1 remains the independent verified 6236-verse text for existing search and text features. Its text is not used to rebuild the printed face.

The original publisher surah index on physical leaves 634–637 was actually opened at full resolution and its 114 start-page entries checked. `king-fahd-chapter-pages.json` records those entries independently of any font/line database. Selecting a surah at ayah 1 opens its original starting page.

This edition currently has **no verified verse hit coordinates or complete verse-to-page index**. The reader deliberately disables verse selection/highlighting rather than borrow geometry from a different edition. Opening an explicit page works; otherwise it opens the verified surah start for ayah 1 or restores the last page. Opening a search result at its precise verse is not implemented for this edition yet. Page-level accessibility labels are available; verse-level accessibility, audio and tafsir overlays remain incomplete.

## Acceptance evidence

Original page 604 was actually displayed and confirmed by the user. Runtime native tests cover all 604 page retrievals and capture pages 1,2,3,151,572,598,604, comparing production canvas PNG bytes with direct CoreGraphics rendering of the exact original. These tests must run on Xcode; adding them does not constitute a passing result. Native canvas run 37504933226 on commit 3f19d569ac928f75b7437920c4c4ee82373c0174 passed all six tests. Its artifact was retrieved and all seven original page captures inspected. Production canvas PNG bytes equal direct CoreGraphics original-PDF output on every sample. Separate MuPDF-reference overlays compare dark lettering and decorations without color or per-line geometry adjustments; rasterization/threshold fringes remain at edges. This is not word-by-word religious certification of all 604 pages.

Full application screenshots were retrieved from run 37506718249 on iPhone 16 Pro Max: page 604 with reader tools shown and hidden. The original page remains wholly visible. The frame-equality test passed when tools hid. The full UI test then exposed a real page-input usability problem: the RTL caret sat before prefilled 604, so entering 572 yielded 572604. The picker now opens with an empty field; run 37509273094 verifies actual navigation through pages 572,598,1 using English and Arabic numerals. That retest is still in progress.

`release/king-fahd-native-review.json` records source hashes, test runs, exact artifact attachments, crop geometry and remaining limitations. Before evidence is the actual old canvas on commit c395914b36a712ace699746cf8189eb8f13604e2; it is not a full application screenshot. Full-page and detailed comparison evidence must not be confused with generated layouts or non-Quran geometry fixtures.

The publication gate remains closed. The source identity is confirmed, but redistribution permission and remaining interaction/visual-review requirements have not been cleared. Historical Ayah before comparisons are retained in `release/mushaf-before-comparison.json`; they are not after evidence for this edition.
