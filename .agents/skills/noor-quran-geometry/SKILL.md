---
name: noor-quran-geometry
description: Diagnose and verify Noor Alruh's native Quran font, layout, page-turn, touch and word-highlight changes against its pinned edition.
---

Use the existing UIKit/Core Text reader; this skill does not authorize replacing it or editing Quran text.

1. Read `docs/release-acceptance.json` QUR items and the actual source diff. Identify edition/font/map hashes and the commit being tested.
2. Inspect `InteractiveMushafCanvas.swift`, `InteractiveMushafReader.swift`, and the relevant original page/word maps. The fixed 560×940 template, authored rows, and uniform viewport transform are distinct from varying ink bounds.
3. For colored fonts, measure the actual COLR layer paths at CTRun positions before the single page-wide font fit and row alignment. Base-glyph bounds alone reproduced ten real page biases. Companion blank glyph IDs are not page-font COLR IDs.
4. Keep V2 heading references, word identities, and the same paths for painting, hit testing and highlighting. Do not introduce per-row font fitting, arbitrary offsets, raster Quran pages or text normalization in display resources.
5. Run the affected native selectors through `scripts/test-mushaf-closure.sh` and inspect the exact source-bound original PNGs/video. Windows grammar checks are not Xcode execution; a geometry pass is not visual acceptance.
6. Record the exact scope and remaining failures in the central ledger. A blocked or incomplete lane stays failed/incomplete.

**Verification examples:** the original `8a190fc` native run 39499805366 passed 23 geometry cases including all604 V2/V4 light/dark, but the full job was incomplete. The existing validator regression `test_normal_page_cannot_replace_missing_tajweed_capture` deliberately substitutes evidence and must be rejected. Run `python -m unittest discover -s scripts/tests -p test_mushaf_closure_evidence.py -v` for these isolated fixtures; they are not app screenshots.

**History:** 2026-10-31: derived from the original COLR failure and subsequent all-page evidence. Resource identity remains the manifests in `release/`; this instruction file is not a new edition or visual approval.
