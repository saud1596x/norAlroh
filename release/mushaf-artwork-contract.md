# Confirmed original King Fahd Mushaf

The user confirmed the displayed original page 604 from **KFGQPC المصحف العادي / standard39-2.pdf**. This supersedes the earlier request to reconstruct the Ayah screenshot's artwork. No claim is made that these two references are identical.

## Source and installation

Official source: https://qurancomplex.gov.sa/wp-content/uploads/isdarat/hafs/standard39-2.pdf

Hash-verified transport mirror: https://cdn.quran.ws/KFGQPC/resources/quran-hafs/standard39-2/standard39-2.pdf

SHA256: `5c4297de1fb6b654f641eed33242408d89432cbecf8a96ff5d297cb45fea7f07`; bytes: 243520529.

Run `python3 scripts/prepare-king-fahd-mushaf.py` before XcodeGen, or pass `--source` for an already downloaded exact original. The preparation script copies the full original unchanged. It refuses size or hash mismatches. The large reproducible PDF is not committed to Git.

The document has 640 physical leaves. Printed Quran pages 1–604 occupy physical leaves 4–607 (one-based). The runtime verifies hash, total leaves and all 604 media/crop boxes and rotations before activating it. The audit records all original image dimensions. This is structural verification, not a claim of human review of all 604 pages.

## Rendering

CGPDFPage draws the original publisher content including paper, frames, surah titles, basmala and ayah markers. There is no font substitution, OCR, text regeneration, manual spacing or per-page exception. One uniform scale fits the complete original page. Reading tools reserve fixed margins, so showing/hiding tools does not reflow the page. Page number navigation, saved last page and zoom are implemented.

The source is raster artwork embedded in PDF, not vector lettering. Zoom cannot recover detail beyond the original raster resolution. Original colors are retained.

## Interaction boundaries

Tanzil Uthmani 1.1 remains the independent verified 6236-verse text for existing search and text features. Its text is not used to rebuild the printed face.

The original publisher surah index on physical leaves 634–637 was actually opened at full resolution and its 114 start-page entries checked. `king-fahd-chapter-pages.json` records those entries independently of any font/line database. Selecting a surah at ayah 1 opens its original starting page.

This edition currently has **no verified verse hit coordinates or complete verse-to-page index**. The reader deliberately disables verse selection/highlighting rather than borrow geometry from a different edition. Opening an explicit page works; otherwise it opens the verified surah start for ayah 1 or restores the last page. Opening a search result at its precise verse is not implemented for this edition yet. Page-level accessibility labels are available; verse-level accessibility, audio and tafsir overlays remain incomplete.

## Acceptance evidence

Original page 604 was actually displayed and confirmed by the user. Runtime native tests cover all 604 page retrievals and capture pages 1,2,3,151,572,598,604, comparing production canvas PNG bytes with direct CoreGraphics rendering of the exact original. These tests must run on Xcode; adding them does not constitute a passing result. Native after captures, viewport screenshots, overlays and human visual inspection remain pending until their artifacts are retrieved.

The publication gate remains closed. The source identity is confirmed, but redistribution permission and remaining interaction/visual-review requirements have not been cleared. Historical Ayah before comparisons are retained in `release/mushaf-before-comparison.json`; they are not after evidence for this edition.
