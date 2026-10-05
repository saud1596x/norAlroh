# License

This repository contains two distinct types of content with different licenses.

---

## JSON Data & Schema

MIT License

Copyright (c) 2026 Mohamad Hajj Rabee

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

This MIT license applies to the following files and folders:
- `pages/` — per-page JSON data
- `index.json` — chapter metadata index
- `verses.json` — verse lookup index
- `font-map.json` — page-to-font mapping
- `qbsml.json` — decoded QBSML surah/juz-header glyph set

---

## Font Files

The font files in `fonts/` and `fonts-woff2/` are **not** covered by the MIT
license above.

The QCF4 fonts are based on the Madinah Mushaf (1441 AH), with calligraphy by
**Uthman Taha**, produced by the **King Fahd Quran Complex**
(مجمع الملك فهد لطباعة المصحف الشريف), Madinah, Saudi Arabia.

The WOFF2/TTF font version was prepared by **Ahmad ElGharib**
([Telegram](https://t.me/quranfont)).

These font files are provided solely for Quranic rendering purposes.
Redistribution, modification, or commercial use of the font files without
explicit permission from the original rights holders is not permitted.

## Noor Alruh QCF V2 distribution record — 2026-10-05

The current reader uses QCF V2 page fonts from Quran Foundation's documented
CDN, not the QCF4 or decorative surah-header fonts discussed above.

Source: https://verses.quran.foundation/fonts/quran/hafs/v2/ttf/
Terms: https://api-docs.quran.foundation/legal/developer-terms/
Reviewed terms date: 2026-10-04; review date: 2026-10-05.

Under section 3.1, font bundling is conditional on an active Developer Console
account and accessible Quran Foundation attribution. Fonts may be distributed
only integrated into the application, never as a separate download or dataset.
This record is not a sublicense or independent permission from KFGQPC.

The pinned 604-file inventory and SHA-256 hashes are in
release/qcf-v2-manifest.json. CI retrieves those exact fonts for the app bundle.
No font archive is distributed in this repository.

Quran glyph data comes from Content Sync at runtime, with complete validation,
atomic offline storage and refresh attempts after seven days. It is not bundled
at build time. Text is not modified. Derived page headings preserve verse order.

Quran Foundation is credited in the application's sources screen. Original
Quran calligraphy: Uthman Taha / King Fahd Quran Complex. Flexible text and surah
headings use the separately licensed Amiri font.

The publisher must keep the account active and comply with current terms.
Specialist religious review and physical-device validation remain separate.
