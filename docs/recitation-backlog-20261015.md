# Recitation backlog and privacy changes

The latest-only mailbox could discard intervening speech while the model warmed
up or a decode ran slowly. Original recording PCM remained on disk, but the live
tracker could jump from its first window to a later eight-second window.

The mailbox now coalesces only windows whose replacement preserves contiguous
audio coverage with one second of overlap. At most eight windows are retained.
Overflow or a discontinuity explicitly makes recognition unavailable while
recording continues. Confidence, timing, Quran alignment, and evidence
persistence requirements are unchanged. This is not a new acoustic model or a
claim of improved population-level recognition accuracy.

Four new scheduling regressions check cold preparation, unchanged frame data,
normal low-latency delivery, and visible overload/discontinuity. Generated sample
values in these tests exercise scheduling only, not acoustic recognition.
The bounded `recitation-engine-check` Release workflow additionally runs actual
bundled reference speech through Core ML, short windows and silence, whole-Quran
anchoring, and provisional edited-reference assessment. Its result is pending.

Content-provider names were removed from both account and guest privacy text.
Microphone, local processing, network request, automatic audio-cache, deletion,
and optional account-processing disclosures remain. Required attribution remains
in the terms. Generated website files are local; no website deployment occurred.

The prior run on source 3253272 compiled and ran 24 unit cases (23 passed, one
failed with two assertions) and one passing UI journey. Its remaining failure
is selection overlap with neighboring ayat on page 151. That failure has not
been fixed by this engine change. The full release gate and physical microphone
acceptance remain outstanding; TestFlight 21 is still the published build.
