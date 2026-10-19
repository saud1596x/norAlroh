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
| Repeated lexical work during live tracking | Source11b prepares the exact-scope wording index lazily, reuses only reference data across windows, and clears it on scope replacement/finish. Empty/insufficient observations are checked before a full-Quran index is built. Speech and findings are never cached. GitHub39191751321:31portable production Swift cases passed; exact77429-word benchmark findings identical,3uncached evaluations1.176206523s versus3cached0.002842295s on Linux. Matching iOS39191751282 passed46units+4UI. | Full-product Release and natural-learner evaluation remain separate. The CPU figure measures lexical work, not phone/ASR speed or learner accuracy. |
| Starting from a complete very short ayah cannot locate the passage automatically | The whole-Quran tracker required three groups for distant positions, so a complete unique one/two-group ayah could never independently satisfy it. New draft binds exact validated native verse boundaries and admits complete short ayahs only with stronger accepted-observation confidence; single words must have a unique corpus start, and shared two-group/compound alternatives still compete. Initials, partial verses, weak observations and repeated phrases stay unresolved. | Eight portable policy regressions and a check of every ordinary short-ayah spelling in the full installed edition are written, not yet executed in Swift/native. No acoustic/model or quality claim; do not publish this draft before actual matching execution. |
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

Source80f native run39185468870 was canceled after preserving its four actual
integration failures; its partial observed passes are not complete acceptance.

Current dfd8db0 focused run39188640033 succeeded on iPhone17Pro/iOS26.2,
Release/accounts project:30unit/policy cases,4separate actual UI invocations,
0failures. This includes the four previously failing integration contracts,
capture-clock2.950s, interruption ownership0.001s, actual reference
pause/restore/resume/finish29.412s, drain-timeout5.034s and hung-recognition
late-result rejection0.712s. First OS approval47.253s, one-tap70.912s,
background/resume79.765s and privacy35.426s are complete UI test durations,
not microphone startup/recognition latency. Every invocation returned0.
Original artifactSHA256
e34c666d569e92f9bb10ec6e3d70615139e3372ecf08833042de6100dc5327d9.
Original exact viewport equality passed. The new lazy-index draft above is
not in this tested source and must receive its own execution evidence.
Whole-product/native integration is still separate; natural learner accuracy
and physical-device acceptance remain unestablished. InstalledTestFlight24
is unchanged.

Source11b00b2 focused run39191751282 also succeeded:46unit/policy cases
and4actual microphone UI invocations,0failures, all process exits0 on
iPhone17Pro/iOS26.2, Xcode26.3, Release/accounts project. Total run24m31s.
Original artifactSHA256
468cd666cb8ac05d90a1d65c51924b337f663196a208ad38189c4999ee40a5bc.
The unchanged first-Allow assertion reached captured0:05 from the original
tap and retained exact original page geometry. Its original screenshot was
inspected; the low-input hint reflects quiet Simulator input, not learner ASR.
This verifies the11b controller/index change; the newer short-ayah draft is
not included. Full native/integration runs39191751250/39191751348 remain
separate and were still in progress when this result was recorded.

Resumed audit19October: both older11b broad runs were subsequently cancelled.
Source474375f portable lane39194329570 passed39cases, including8short-ayah
regressions; all278ordinary short-ayah spelling forms were checked with
injected accepted observations (251located,27abstained,0wrong bindings).
These are location-policy checks, not speech-recognition accuracy.

Matching474 focused run39194329538 failed overall. Its54unit cases and all
four UI case bodies passed, but the background xcodebuild invocation exceeded
its180s process deadline after the77.880s case body had completed. Preserve
exit124; do not turn a completed case into a successful invocation. Original
artifactSHA256e3ae7430ecb9465f09c6d18b149b137d47b91a6c7b04a1b93e4101c75f29b237.
Full native39194329568 was cancelled at1h5m; separate accounts/extensions
build passed7m46. Neither is a full-product acceptance pass.

Integration39194329555 compact actually executed396unit cases,2skipped,
4assertion failures: three assertions in the real-PCM cross-surah session
and one obsolete privacy-title assertion. The two real reference clips were
only located after their original20s deadline, leaving the display one clip
behind; explicit finish later found the final verse. Do not increase that
deadline or replace the acoustic input. New acceptance-only numeric stage
traces distinguish pinned asset hashing, CTC model loading, primary loading
and paired decode completion. They do not change runtime inference behavior.
A focused Release diagnostic retains the unchanged real-PCM test. Privacy
tests and accounts policy now describe temporary live audio and automatic
cleanup instead of the removed recording-library workflow.

The restored local FP32 CUDA export reproduced the pinned d854e74f digest;
22raw-recognition parity cases passed separately. A subsequent professional
alignment audit was INVALID: child Python used Windows cp1256 to read the
UTF-8 vocabulary, making its Arabic alphabet empty. Those rejections and
negative-control rows are setup errors, not acoustic evidence. All vocabulary
readers now explicitly useUTF-8, invalid canonical setup aborts the audit,
and library resume fingerprints include actual CUDA/cuDNN package versions.
27local regressions plus4subtests passed, including the actual non-UTF8 child
boundary. No professional timing candidate was promoted or shipped.

Matching47dcd82 diagnostic39286866596 succeeded:6Release cases,0failures,
including the unchanged real-PCM cross-surah deadline and all5publishing
content cases. iPhone17Pro/iOS26.2, Xcode26.3; artifactSHA256
a84796dd2bc4f1087e2db95266abf7c3aeda5df8aaf14cac584bf3888adf05b0.
The first location arrived20.622s after fixture injection, the second6.493s;
the nominal20s polling test passed under its original loop, but these wall
times are not an instant-recognition claim. Independent assets hashed2.922s,
its model loaded between3.292s and14.182s; paired preparation15.774s.
Paired windows returned in2.189–4.288s. This identifies cold loading and
inference costs; adding stage diagnostics did not fix them. Whole-product
and focused UI invocations remain separate from this six-case result.

The user's visible-text request now has a specific controller-to-canvas
regression: keep every ayah visible, follow the exact accepted word into the
next ayah, retain the completed ayah when visibility toggles, and preserve
all original glyph regions/row ink/shaping passes. Public PCM supplies
capture/VAD, while observations are explicitly injected; it cannot prove
acoustic recognition accuracy. Native execution of this new case is pending.

Published-coordinate tooling also audits QUD-Technologies' Quranic Universal
Audio v3.2.0 (https://github.com/QUD-Technologies/quranic-universal-audio/releases/tag/v3.2.0).
The publisher releases code/timing metadata under CC-BY-4.0; source audio
rights remain with its original providers. Only data was read, no publisher
helper was executed. Exact package/script hashes are pinned in
tools/reciter_alignment/published_coordinates.py. This tool accepts only
Noor's existing authored aliases and exact native IDs, retains source clock
gaps and explicitly timed reciter repetitions, and leaves mismatched verses
unmapped.12local regressions passed. On the actual pinned script,6072/6236
verses mapped uniquely;164remain unresolved. Huthaifi6072occurrences/77796
timed spans and Shuraim6095occurrences/76031spans cover114surahs each at the
publisher-coordinate level. Their exact audio identity relative to the app
is NOT_VERIFIED, and no timing was integrated/promoted. These numbers do not
establish all20readers or audio review. The corrected20reader acoustic audit
is separate and retains measured candidates, exclusions and negative controls.

Follow-up19October: exact expansion of explicit dagger-alif alternatives on
both sides, and counting whitespace tokens inside an already authored alias,
maps6149/6236verses;87remain unresolved. It does not add fuzzy spelling rules
or modify Quran text. All228current chapter URLs for Huthaifi and Shuraim
were checked against the publisher's redirect destinations: each resolved
to the exact existing app catalog resource. This is URL/source identity,
not an independent audible review or a permanent byte-hash guarantee.

The new bundled surah-word-timings.json imports156624exact published spans
for those two recording identities across114surahs each. Unknown87verse
coordinates, their repeated occurrences, and Shuraim's untimed Fatiha
basmala remain absent. Actual timed repeats and gaps remain explicit. The
runtime follows real player time, pins the resource and native edition,
rejects changed recording identities/truncated media, and never treats
reference playback as learner evidence. Metadata attribution and changes
are retained under CC-BY-4.0, copyright Wider Community. This is partial
published playback guidance, not all20readers or acoustic certification.
22resource/payload regressions and38alignment tests plus9subtests passed
locally. Six modified Swift sources passed grammar parsing only; native
compilation, resource loading and UI execution remain pending.

Matching47dcd82 live run39286867493 failed its unit invocation(exit65).
All4separate UI invocations passed, including the original first-Allow
assertions. The first startup-barrier failure threw before releasing or
joining its delayed task; later capture cases then failed and the test host
restarted. The restarted28-case pass summary is not a pass for the complete
invocation. Cleanup now releases and joins on failure, and the gate latches
an early release. A storage-only PCM byte-count test now injects a no-op
preparation provider instead of inadvertently loading acoustic models.
Neither change proves the original startup cause or fixes acoustic accuracy.
Acceptance-only numeric startup traces identify the actual next boundary.
The reader also prepares its immutable validated text/ID index after the
page/font becomes ready, so it can be reused on microphone entry. No audio,
acoustic model or network starts in this preparation. Its effect on latency
is not yet measured.

The user's32-second reference video is Tarteel, not a Noor defect capture.
It demonstrates interactive page panning, text concealment at fixed ayah
positions and inline microphone controls. Its premium panel describes
wrong/missing/extra word detection and feedback; merely displaying that
panel is not accuracy evidence. No private video/audio was uploaded or
transcribed. Current-source verification reuses existing all604colored
canvas geometry tests, full-face page14, immediate reader entry and actual
normal/colored/selection/page-turn UI captures as separate bounded scopes.

Subsequent5292a20 focused run39290963318 completed55unit cases with0failures,
including the visible-text test(3.144s). One-tap, privacy and first-Allow
invocations exited0. Background case body passed87.787s, but xcodebuild had
not exited before the original180s process limit; preserve exit124 and the
overall failure. This success/failure pattern does not prove a deterministic
startup defect or warrant weakening the original live deadlines.

The47dcd82 full compact integration executed396cases,2skipped,8assertion
failures:3actual-PCM cross-surah deadline/order assertions and5location
timeout/retry assertions. All604normal rendering, all604colored geometry,
and13viewport tests passed in that source, not the subsequent timing draft.
Large also exited65; its exact assertion list has not yet been inspected.
Native checks39286866668 stopped before native execution because2publishing
fixtures compared current generated privacy/support text with stale tracked
pages. Regenerating those offline pages from the existing source policy
resolves that mismatch without deployment or changing policy requirements.

The user's next direction changes the exposed catalog: keep only recordings
with actual word-timing resources and remove unsupported choices. The Mushaf
picker now offers3published EveryAyah identities plus the2exact published
whole-surah identities(Huthaifi/Shuraim). These5recordings represent4voices;
they are explicitly labelled partial coverage, not fully reviewed/full-Quran
word timing.18whole-surah and2EveryAyah untimed options are hidden. Older
untimed preferences cannot insert themselves back into the picker, and direct
selection rejects unsupported recordings. Original cache keys/bytes and the
raw20-recording source catalog remain intact, never relabelled or deleted.

The library exposes only its2whole-surah word-timed sources and opens the
existing Mushaf with the exact selected identity. It no longer starts an
independent audio-only player that has no visible word cursor. Opening the
Mushaf itself does not start audio or microphone capture. Native/UI tests
now cover removed entries, exact source and bitrate separation, preference
restoration, and the library-to-reader handoff. Native execution is pending.

Primary-source research19October compared QUL's With-segments resources,
Quranic Universal Audio v3.2.0 and Quran Foundation's Audio API. All require
matching timestamps to the exact media and word coordinate family; a voice
name or available audio link alone is insufficient. QUL116was downloaded as
data only(archiveSHA653406f2c8f882ed2233b722b712bb4bca6d5faeb6698f86a913b4761e8461cd).
It has6236rows/78010spans, but a direct Tanzil-coordinate audit found368rows
with numbering/overlap mismatches. This is not a claim that QUL's own source
is inaccurate; its coordinate convention differs. It was NOT imported or
applied to the existing EveryAyah/MP3Quran media. QF's current API requires
backend credentials; no new credentials/service were created or exposed.
Apple SpeechAnalyzer and the gated FastConformer candidate remain research
candidates, not measured Arabic Quran accuracy or implemented replacements.
