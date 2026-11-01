---
name: noor-reciter-timing
description: Repair Noor reciter playback, word/ayah clocks, seeks, observer lifetime and page following while preserving exact recording and native Quran identities; not learner ASR evidence.
---

# Noor reciter playback and timing

Read the current REC/audio acceptance items before changing playback or timing resources.
Keep Swift5/iOS17 and existing audio-focus ownership; this skill adds no dependencies or permissions.

- Trace `MushafVerseAudio.swift` through `NoorSurahWordTimings.swift`, `NoorSurahAyahTimings.swift`, `NoorReciterWordTimings.swift` and reader following. Bind each clock to the exact reciter ID, recording ID, server/file identity, duration and pinned source; a voice name or surah number alone is insufficient.
- The actual edition bridge previously excluded 87 genuine ayahs. Preserve `tools/reciter_alignment/published_coordinates.py` and its exact coordinate/string tuples; no fuzzy/global letter folding, borrowed basmala, interpolated spans or changed publisher integers. Preserve repeats and silence gaps.
- Validate finite media times against the current item. Derive word/ayah state from that recording's current media clock, never wall time, callback count, a timer's nominal interval or synthesized progress. Clear word highlighting during gaps, invalid clocks, waiting, pause and seek.
- Retain each periodic-observer token with its creating AVPlayer; remove it exactly once on that player before replacement/release. Use a serial callback queue. Repeated setup must not overwrite a live token; removal can leave an in-flight callback, so retain generation/player/item guards after actor hops.
- Invalidate seek/load generations on stop, replacement and reciter change; cancel obsolete work and pending item seeks where applicable. Publish seek completion only if `finished` and current generation/player/item still match. A late completion must not restart playback or restore an old word.
- Preserve pause/resume, interruption, route-loss and background intent through `NoorAudioFocus.swift`; recording must exclude reference playback. Do not auto-resume merely because an interruption ended. Keep current stop/error deadlines and explicit user actions.
- Preserve reader selection, page-turn cancellation and playback locks in `InteractiveMushafReader.swift`. Missing/gap timing cannot jump to ayah1 or borrow learner-ASR location. Only current eligible playback may follow pages; never animate Quran text or word positions.
- Update Now Playing from actual finite item time, duration, rate and transport state. Retain/remove only this owner's remote-command targets; never `removeTarget(nil)` across owners. Use semantic Arabic controls and distinguish reciter playback from microphone/learner evidence.
- For resources, inspect `scripts/import-published-surah-word-timings.py`, the source receipt and coordinate bridge under `content-sources/reciter-timings/`. Preserve recording/source/native-snapshot hashes, licenses and `scripts/verify-release-ipa.py` bundle-byte/resource checks; a source-tree file alone is not archive proof.
- Report 114-surah, 6,236-ayah and 77,429-native-word coverage separately per recording. Check excluded tracks, missing Shuraim first basmala, repeats, gaps, truncation and changed URL/bitrate; never promote partial coverage into all-reciter support.
- Use `NoorReciterWordTimingTests`, `NoorReciterTests`, `NoorReaderCoreRegressionTests` and `MushafViewportTests`, plus `scripts/tests/test_published_surah_word_resources.py`, `test_reciter_timing_resources.py` and `test_surah_ayah_timings.py`. Source/clock fixtures do not establish audible alignment, live microphone accuracy or learner credit; require matching native archive/results and actual acoustic QA separately.

Apple ownership contracts (verify current SDK signatures before changing code):
- [Periodic time observer](https://developer.apple.com/documentation/avfoundation/avplayer/addperiodictimeobserver(forinterval:queue:using:)) and [removal/in-flight callbacks](https://developer.apple.com/documentation/avfoundation/avplayer/removetimeobserver(_:)).
- [Pending-seek cancellation](https://developer.apple.com/documentation/avfoundation/avplayeritem/cancelpendingseeks()) and [remote target removal](https://developer.apple.com/documentation/mediaplayer/mpremotecommand/removetarget(_:)).

Windows permits source/resource checks; it has no AVPlayer, iOS Simulator or Swift compiler. Installing or reading this skill closes no audio/model-quality gate.
