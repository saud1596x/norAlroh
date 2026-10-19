# Live recitation — unresolved gaps and acceptance evidence

User direction: real recitation inside the existing Mushaf, with no new
recitation screens or further cosmetic redesign. Resolve and verify each gap;
do not count a successful compile or a narrow suite as complete acceptance.
Use GitHub for further repair verification. No App Store release.

| Gap | Current implementation and actual evidence | Still required |
| --- | --- | --- |
| Original microphone tap | Async hardware startup, no model-load dependency before capture, input-only session. GitHubcb first-Allow UI passed with real OS approval, captured elapsed0:05 and no second tap. | Newer functional changes still need their own native verification; physical device acceptance pending. Codemagic672 still SIGABRT in RemoteIO on hardware queue; cannot call this fixed across environments. |
| Capture stops on silence | Empty actual VAD windows now have a real UUID accepted by strict source journaling. Current672 silence/pause/resume regression passed. | Physical-device sustained capture acceptance. |
| Old microphone callbacks stop a resumed take | Every explicit resume now creates a fresh callback epoch. The actual80f native log shows the old-callback/current-input regression passed0.978s. Final audit also removed redundant unscoped UI route/pause observers; capture-owned events already handle these with the epoch guard. | The UI-observer follow-up and interruption ownership regression need new native execution. Injected ownership is not Bluetooth/device verification. |
| Reading journey still links to an unwanted separate memorization history | Final route audit found a remaining link from the home reading journey into MemorizationHistoryView. Removed that entry and corrected the home journey description to reading/khatmah. Existing removed-features UI journey now checks the actual summary area for the obsolete history link. | Current-source native/UI execution. Reading/khatmah progress data remains separate from temporary microphone recordings. |
| Shown ayah disappears | Retain displayed ayahs independently of revisable recognition evidence, without awarding correctness. Current672 original-PCM/injected-word policy test passed, including withdrawal and persistence. | Natural-recitation/device journey; the fixture is not ASR accuracy evidence. |
| Old word remains highlighted | Actual source-clock frontier, conflict withdrawal, same-clock coherent recovery and unlocated-window clearing. Six current672 native location cases passed. | Reviewed natural-learner timing/false-highlight evaluation. |
| Recognizer failure leaves a stale highlighted word | Both error paths withdraw only the active location, preserving prior evidence and shown ayahs. Actual80f native log: regression passed0.965s and shown-Fatiha retention passed1.301s. | Natural learner/device evaluation; these are original-PCM/injected-word display policies, not accuracy results. |
| Page refits when microphone/input hint appears | Separate normal/live control reservations; concise hint uses existing header row. GitHubcb first-Allow passed the original exact frame-equality assertion. | Physical-device/other-size acceptance; never weaken equality to hide a jump. |
| Slow or inaccurate first recognition | Capture is independent of ASR, bounded mailbox retains original input across cold preparation. Actual old GitHub independent warmup took25.81s; that is not an iPhone latency estimate. | Measure capture-to-first-word latency and error/abstention rate on held-out authorized, labeled learner speech. Cold-start/throughput success alone is insufficient. |
| Capture timer freezes during model preparation | Monotonic frame count now comes from already-written original PCM. Actual80f native log: blocked-preparation regression passed1.005s. The239 focused invocation was interrupted by its180s aggregate process deadline after cold host launch; it did not print an assertion failure. | Focused suite recheck with separate bounded aggregate budget and process timestamps; not an inference-speed improvement. |
| Manual page turn during one live ayah loses following until the next ayah | Reader previously observed only currentVerse for live navigation. It now also observes the actual active word and resolves its exact native page within that same verse. Missing/unrelated cursors cannot navigate or leave a daily range. Regression uses real bundled page4 and a page3 daily-range rejection. | New-source native and reader acceptance; this is navigation policy, not acoustic accuracy. The original split-ayah hypothesis was disproved: all6236verses in this edition have lexical words on one page each. |
| Live navigation replaces the ayah whose tools are open | Guard live following while the user has a manual ayah selection or sheet open. Exact source policy rejects navigation during that selection and permits it after closure. | New-source native execution. No new screen or layout redesign. |
| Legacy integration expectations conflict with live-only recitation | Actual80f native log exposed four failing integration cases: two read audio/journals after explicit finish deletes them; two request default visible text but expect hidden unread words. Move actual PCM/evidence checks before finish, assert files cannot reopen afterward, and explicitly opt into hidden text in hidden-text cases. Retired self-recording-player assertion replaced by actual original-byte/PCM-length checks and mandatory deletion checks. | All four real/injected-boundary integration cases remain selected in the focused suite and require a successful new native result. No app cleanup or visibility policy is relaxed to accommodate old tests. |
| All professional readers follow every word | Audit enumerates20readers ×114surahs =2280recordings with exact source hashes and negative controls. Development candidates remain separate from production. | Complete every recording, review actual word intervals, integrate approved exact recording/clock bindings and test app playback. No all-reader completion claim from partial machine candidates. |
| Repeatable test/build | Converter TLS roots verified; original float32 graph/weight pins unchanged. Exact one-byte auto conversion-date drift identified from original artifact; original edition date and actual regeneration timestamp now separate. Current672 bundled-asset gate passed. | Matching current native/acoustic/UI results. Normal reviewed-release gates remain unresolved; installed TestFlight24 is old. |

Current native receipt: `outputs/native-672-evidence/receipt.json` in the
workspace (not a committed test fixture), build6ad565d27550aed8108ff9e7,
source6722b451c9e2f81fbd4e9aad79d37c9c02301db0:18cases,0failures,
13.738s. Actual first-Allow UI failed after83.804s, RemoteIO RPC timeout.
The independent scoped acoustic check6ad5670b7550aed8108ffa06 passed73cases,
0failures,80.523s on672. Original archiveSHA256
9b3b6aa907666f350997a12e1f7c773c64d6acca930ea0b8eb726a9c0a1ec164.
It does not include the newer failure-highlight or capture-clock changes.

GitHub run39182166954 atcb06ac2988148e5f9ea27f49c293488e0ee19f6e
passed the full selected live journey:21unit/policy cases,4UIcases,0failures.
Original archiveSHA2569f4f723f1848838cb45ac8f660a18379dd30a9af7e2e37825798078995374aa0.
First-Allow43.415s, one-tap45.286s, background/resume71.004s, privacy29.137s.
Its app/tools/scripts/resources are identical to672; only workflow triggers
changed. These are simulator capture/lifecycle results, not natural speech
accuracy. New failure-highlight and capture-clock verification remains pending.
The focused e09 run39183130158 stopped at the720-second build deadline before
any unit/UI test executed. Original archiveSHA256
f5bec6a4cfd5cac7b7e1387802c746d65db2d6763cf5c2b5a31486ed136e3624;
context results is empty and build.txt ends at AtharTests compilation. This is
not a passing regression or a demonstrated acoustic failure. Cold Release
compilation now has a separate bounded1200-second lane restricted to
`xcodebuild build-for-testing`. Per-test execution deadlines and assertions
remain unchanged; timeouts still fail. Five local deadline-policy checks passed.
No new TestFlight upload is claimed. Natural learner accuracy, Tajweed
assessment, complete all-reader word timings and complete product Release
acceptance remain unestablished. Further repair verification uses GitHub per
the user's latest instruction, without starting more paid CI attempts.

Newer239 focused run39185242274 failed its180-second aggregate unit-process
deadline. Seven cases completed before the interrupted capture-clock case;
remaining selected units did not run. All four separate actual UI invocations
passed: one-tap51.817s, background/resume77.682s, privacy27.466s,
first-Allow51.465s, with original exact page-frame equality. Original archive
SHA2569270759f5a69c9ba8b9f0bf9bdf4724d8d3a0485d2dd1244cdbd908a045f2108.
The last build timestamp is01:40:48.543UTC; the unit suite first starts
01:43:42.522UTC. The outer budget includes test-host installation/startup.
Exact process start was not instrumented, so this does not establish a180s
case hang. The focused multi-case unit invocation now has a600s aggregate
budget; each case retains its original100/120s XCTest limit and single-UI
invocations retain180s. Timeout still fails. Six local wrapper tests passed,
including actual termination/failure propagation. Stage-only timestamps were
added to the fixture; no user audio or transcript is logged.

Source80f native run39185468870 is still being collected at this update.
The visibly observed native passes above are not a successful complete run:
the same log contains the four integration failures described in the table.
Current follow-up changes have no passing native result yet. Installed
TestFlight24 is unchanged.
