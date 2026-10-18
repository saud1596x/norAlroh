# Integrated beta acceptance, after build 24 device complaints

Destination explicitly reconfirmed by the user: **TestFlight only**. No App Store
submission. Do not publish another incremental build merely because one focused
check passes. The user requests whole journeys and confirmed defects repaired.

## Current evidence and outstanding work

| Area | Evidence | Remaining acceptance |
|---|---|---|
| Main microphone activation | abfe530: normal Button + immediate haptic action; actual OS permission/denial UI passed | Actual permitted simulator capture, stop and background/resume journey; physical device remains separate |
| Learner recognition | abfe530: genuine public PCM, dual-source/original-clock/omission/quiet controls passed; first112:1 at13.554s, next114:1 at3.791s | Natural learner accuracy, real phone latency/memory and pronunciation assessment remain unestablished; these two clips are not a general benchmark |
| Scripture startup | Exact bundled edition reused offline; local reopening with failing network callback passed; no model warmup during reading | Cold physical phone startup measurements |
| Page turns | Actual eight swipes14→18→14 passed with fixed canvas frame; action-to-assert durations1.64–1.94s include XCTest overhead | Real device frame pacing and long reading sessions; no FPS claim from XCTest durations |
| Native reader layout | Current original page14 screenshot reviewed; earlier all604 normal/Tajweed geometry evidence retained by its own source | Current broad picker/Tajweed route and physical reading comfort |
| Professional reciters |20 complete114-surah catalogs, exact recording identity guards; no guessed clock substitution | **Full verified word tracks for all2280recordings remain incomplete**. Previous local full pass stopped for disk reserve; partial candidates are not production proof |
| Daily ward | Reading-only plan and20-page boundary tests exist | Re-execute complete home→ward→stop→resume→confirm journey on current runtime |
| Adhkar | Morning/evening separate sessions implemented | Re-execute both readable sessions and Arabic search/counter journey |
| Prayers/reminders | Deterministic scheduling, after-prayer20minute delay, silent salawat and reconciliation tests exist | Re-execute logic with current app; physical OS delivery/sound remains separate |
| Account/privacy | Real optional-account implementation and prior signed Firebase inclusion | Account screen/deletion-state/navigation checks; real Apple sign-in/sync/deletion E2E is not established by unsigned UI tests |
| Navigation/settings | Actual complete walkthrough exists | Re-execute current route through home, Mushaf, prayer, adhkar, settings, privacy/terms/support |
| CI coverage | Found three obsolete method selectors in older scripts; corrected to the actual inline-reader tests; new preflight validates188literal selectors locally | Actual execution counts/results must still be retained. Static selector discovery never certifies execution |
| Overall release | Current scoped check80unit+3UI/0failures in original downloaded artifact; no new IPA | Complete outstanding acceptance and honest scope before selecting a next beta; full Release suite is not passed |

## Current paid check

`device-reported-reader-repair-check`, source
`abfe530fc9147e79a5bbcf8438c116cf98182eec`, Codemagic
`6ad526dc7550aed8108feda6`: finished13m30s,80unit/0failures in58.101s and
3UI/0failures in70.297s. Original logs and4native screenshots were downloaded
to `outputs/build24-repair-abf-evidence`; no screenshots were regenerated.

The next bounded integrated-journey check preserves failures independently:
navigation/logic and permitted microphone result bundles have separate exit
codes. No fake permission, PCM, audio completion, progress or live account login
is injected into application state. Simulator OS permission is granted using
simctl explicitly for the genuine capture journey.

Independent raw AVPlayer/AVAudioPlayer host diagnostics previously stalled;
do not repeat those unchanged diagnostics or erase their failure records. The
new microphone path is specifically different: no system playback cue precedes
capture. That changed path needs its own actual permitted-capture evidence.

The50additional-feature ledger is still incomplete. Do not mark planned
capabilities verified from these narrow tests or describe this beta as a fully
calibrated Quran/Tajweed engine.
