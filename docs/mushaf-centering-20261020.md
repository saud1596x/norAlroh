# Whole-Mushaf centering correction — 20 October 2026

## Actual defect and requested behavior

The user rejected the actual page 14 phone image and explicitly requested the
same correction throughout all 604 pages, including titles and basmalas. The
previous native image remains a failure reference, not an approved baseline.

The native 560×940 page 14 bitmap has dark body ink approximately x33…545,
whose raster center is 289 instead of 280. Independently, pinned V2 outlines
approximate the widest authored row as 512.3712 units. Aligning that block to
the old fixed right edge 545 gives a center 288.8144. Centered source rows,
titles, basmalas and ornaments already used 280, so moving the entire viewport
could not correct their disagreement.

The SwiftUI surah header had a separate cause: ordinary HStack spacers centered
it between unequal side controls rather than on the screen axis.

## Production correction

- Retain the fixed 560×940 edition frame, body size 32, baseline interval 61, original
  words, row ordering, glyphs and authored centered/right-aligned distinction.
- Measure the original V2 whole-row glyph bounds using Core Text and the
  original companion separator font. Let W be the widest authored ayah row.
  Use one shared body right edge `280 + W/2`. Centered source rows remain on 280.
  This centers the complete block without centering each right-aligned row,
  resizing individual rows or changing the viewport scale by content density.
- For page 14 the resulting right edge is approximately 536.1856; the left and
  right blank margins of its widest row become approximately 23.8144 each.
- Titles and separate basmalas share axis 280. Tajweed keeps the same original
  V2 anchor and heading geometry. Its existing font-metric normalization is
  unchanged; this correction changes neither text nor font resource bytes.
- Fit the complete fixed edition frame with the existing uniform min(width,
  height) viewport rule. Ordinary tools, selection and capture retain their
  reading-space reservation; only explicit full screen can reclaim the lanes.
- Use equal measured side reservations for the SwiftUI header. SwiftUI itself
  mirrors custom Layout placement in RTL; do not manually mirror it again.

## Navigation and reopening in this batch

A cold manual turn previously checked only its request UUID after waiting for
the font. A recognized-word follow could meanwhile change the current page
without invalidating that request. The new coordinator requires the original
request, source page and ownership to remain current. Following, selection,
microphone start, reload and dismissal cancel the old request. A return to the
same page cannot revive it. Existing font preparation can complete safely but
cannot commit stale navigation.

The companion font's hash, PostScript identity and actual UIKit registration
are verified before caching successful registration for this process. Failed
registration is not cached. Reopening does not reread and rehash that immutable
bundled font repeatedly.

## Evidence required, not a completion claim

- The all 604 native V2 test now checks whole body centering, actual placed
  glyph-path centering, a shared right edge, original row alignment, and the
  title/basmala axis separately from ornaments. Existing hit, clipping,
  selection and source-identity checks remain.
- All 604 V4 pages in light/dark also check the actual COLR path union, in
  addition to CTLine bounds, unchanged headings, clipping and readable extent.
  The 0.15 reference-unit tolerance accounts for the existing 0.1-unit V4 extent
  normalization and subpixel measurement; it is not a widened failed criterion.
- Real UI captures on three phone sizes must show a centered page title and
  preserve the Arabic close/right and reciter/left order. Frame, touch, gesture,
  colors and continuous microphone-journey gates remain mandatory.
- Two asynchronous navigation regressions retain delayed completion, canceled
  ownership, same-page return, newer requests, invisibility and playback locks.

Independent FontTools approximation on 39 spread pages found at most 0.0564
units of predicted colored-path bias. It is not Core Text execution or visual
approval. Local Swift grammar and selector checks are not native compilation.
The earlier run 39484685810 / source 582c60f does not contain this correction.
No new TestFlight upload or user visual approval is claimed by this document.
