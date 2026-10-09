# Original Mushaf cached opening — 2026-10-09

Status: source implemented, native Release acceptance on compact and large iPhone simulators PENDING. Not published.

Prerequisite accepted: reminders Run 6 `37877796848`, source `bc8b63c7b7cae582351a03932a623bd11e72a3f9`, compact `113650260287` and large `113650260439` both successful.

Active InteractiveMushafReader and MushafTrainingPage now use one application cache and one actor-prepared reading copy. Snapshot decode/edition validation, authored-row validation and canonical verse/word indexing run outside MainActor. Actual file bytes are SHA-256 checked before reusing verified decoded cache; changed or corrupt bytes invalidate the cache memo. New invalid preparation payloads cannot inherit an earlier successful preparation. The existing seven-day refresh runs in the background when a validated offline copy is available. First opening with no valid copy still requires the original Content Sync download and reports failures honestly.

No glyph, page-font, drawing, layout geometry, colors or religious-text changes. Training now also starts the same seven-day connected refresh. Cancellation is checked before state publication. Companion registration and recitation/audio/restoration logic remain unchanged.

Native gate: exact complete-source SHA marker, Release on both displays; live snapshot with all 604 original pages; prepared 6,236-verse mapping; corrupt/new edition/missing-word/same-timestamp disk replacement rejection; held real-snapshot refresh verifies stale reading returns before the fetch completes; saved reader page opens within 10 seconds after actual process relaunch; existing geometry/tools/gestures/orientation, reminder Save and khatmah-protection regressions. CI result bundles retained by the existing runner; no downloads, images or video sent to the user.

Remaining: native results, requested home/account/tab/reflection route work, resource-specific packaging/companion rights, physical-device services and current signed release. Generic user publication authorization does not establish third-party distribution rights. Store Build 15 is historical and is not this source.
