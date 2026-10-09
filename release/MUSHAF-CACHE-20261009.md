# Original Mushaf cached opening — 2026-10-09

Status: source implemented, native Release acceptance on compact and large iPhone simulators PENDING. Not published.

Prerequisite accepted: reminders Run 6 `37877796848`, source `bc8b63c7b7cae582351a03932a623bd11e72a3f9`, compact `113650260287` and large `113650260439` both successful.

Active InteractiveMushafReader and MushafTrainingPage now use one application cache and one actor-prepared reading copy. Snapshot decode/edition validation, authored-row validation and canonical verse/word indexing run outside MainActor. Actual file bytes are SHA-256 checked before reusing verified decoded cache; changed or corrupt bytes invalidate the cache memo. New invalid preparation payloads cannot inherit an earlier successful preparation. The existing seven-day refresh runs in the background when a validated offline copy is available. First opening with no valid copy still requires the original Content Sync download and reports failures honestly.

No glyph, page-font, drawing, layout geometry, colors or religious-text changes. Training now also starts the same seven-day connected refresh. Cancellation is checked before state publication. Companion registration and recitation/audio/restoration logic remain unchanged.

Native gate: exact complete-source SHA marker, Release on both displays; live snapshot with all 604 original pages; prepared 6,236-verse mapping; corrupt/new edition/missing-word/same-timestamp disk replacement rejection; held real-snapshot refresh verifies stale reading returns before the fetch completes; saved reader page opens within 10 seconds after actual process relaunch; existing geometry/tools/gestures/orientation, reminder Save and khatmah-protection regressions. CI result bundles retained by the existing runner; no downloads, images or video sent to the user.

Remaining: native results, requested home/account/tab/reflection route work, resource-specific packaging/companion rights, physical-device services and current signed release. Generic user publication authorization does not establish third-party distribution rights. Store Build 15 is historical and is not this source.

## Run 1 started

Native run `37879765624`, exact source `8d66a147208c1c05aefb554056c594fd85c7a2e5`; compact job `113656514486`, large job `113656514698`. All 140 source hashes verified against the fetched remote tree before the marker was published. Both jobs observed running; no native success claimed yet.

## Run 1 result and reader-control correction

Large job `113656514698`: SUCCESS, 18m19s. Compact job `113656514486`: failed at `NoorReaderComfortUITests.swift:134` in `requireTools(true)` immediately after the real jump to page 604. This is not cached-relaunch acceptance on compact: it did not reach that assertion. Native selected data tests completed before UI on both. Compact reminder Save/relaunch regression separately passed (289.495s); selected UI total 3 tests, 1 failure. The earlier progress reaching later UI classes did not prove the reader class passed; XCTest continues other classes after a failure.

Actual compact failure hierarchy: window 402×874, page 604 rendered, counter `reader.jump` leaf frame `(137,808,128,20.3)` while next/previous labels were 44pt. The page-picker keyboard window remained in the hierarchy off-screen. This proves the counter label violated the requested 44pt hit area; it does not alone establish the sole reason for the hittability timeout. Correct the production label frame/content shape and explicit input focus dismissal. The fixture now waits for actual sheet/keyboard dismissal and a hittable counter before resuming reader assertions; its existing 5-second tools gate stays unchanged and now additionally requires a real 44pt counter frame.

Also correct loading state: cached preparation says “فتح المصحف…”; only the cache's real no-valid-copy branch starts “تنزيل بيانات المصحف لأول مرة…”. It resets immediately after the download returns. First-use still requires online original data; the message change does not establish bundled data rights. Unit checks verify stale cache returns without a foreground-download signal while the held real refresh starts, and missing-cache offline failure does emit one signal. Run 2 full two-display gate remains PENDING.
