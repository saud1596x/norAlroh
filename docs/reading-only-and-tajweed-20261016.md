# Reading-only daily ward and Tajweed status

The daily ward opens the existing bounded reading scope. It does not expose
recording, reciter selection, repetition or memorization actions, prepare the
recognizer, or restore a pending recitation. Reading tools, tafsir, bookmarks,
the saved stop and explicit daily completion remain available. The unrestricted
Mushaf retains audio and recitation. Native verification is pending for this
change; syntax parsing is not a native build.

Tajweed colors are requested but **not implemented or enabled**. On 2026-10-16,
the actual QUL resource 47 JSON archive was downloaded and compared to the
bundled V2 snapshot: 83,668 V4 records versus 83,665 V2 records including verse
ends; 233 shared location keys have different glyph strings. V4 adds locations
2:181:15, 8:6:13 and 13:37:21. These are edition/tokenization differences, not a
claim that either Quran text is corrupt. Replacing the V2 font directly is not
a valid integration, nor may word IDs be copied by array offset.

Sources inspected:
- https://qul.tarteel.ai/resources/quran-script/47
- https://qul.tarteel.ai/resources/font/240
- https://qul.tarteel.ai/docs/glyph-based

The font resource is available, while the glyph-based documentation still says
V4 is disabled pending proofreading. That conflicting publication status has
not been resolved. A complete implementation needs the matching authored V4
layout, an audited mapping to the app's canonical word IDs, verified resource
distribution terms, and native rendering/selection tests across all pages.
No downloaded V4 resource is included in the app or substituted into V2.
