# Live recitation — unresolved gaps and acceptance evidence

User direction: real recitation inside the existing Mushaf, with no new
recitation screens or further cosmetic redesign. Resolve and verify each gap;
do not count a successful compile or a narrow suite as complete acceptance.
Use GitHub for further repair verification. No App Store release.

| Gap | Current implementation and actual evidence | Still required |
| --- | --- | --- |
| Original microphone tap | Async hardware startup, no model-load dependency before capture, input-only session. GitHub389 reached real OS Allow then elapsed0:05 without another tap. | Current-source complete first-Allow UI pass. Codemagic672 still SIGABRT in RemoteIO on hardware queue; cannot call this fixed across environments. |
| Capture stops on silence | Empty actual VAD windows now have a real UUID accepted by strict source journaling. Current672 silence/pause/resume regression passed. | Physical-device sustained capture acceptance. |
| Shown ayah disappears | Retain displayed ayahs independently of revisable recognition evidence, without awarding correctness. Current672 original-PCM/injected-word policy test passed, including withdrawal and persistence. | Natural-recitation/device journey; the fixture is not ASR accuracy evidence. |
| Old word remains highlighted | Actual source-clock frontier, conflict withdrawal, same-clock coherent recovery and unlocated-window clearing. Six current672 native location cases passed. | Reviewed natural-learner timing/false-highlight evaluation. |
| Recognizer failure leaves a stale highlighted word | Additional audit found both inference-error and mailbox-overflow returns kept activeWordID while recording continued. A shared failure path now withdraws only the active location, preserving prior evidence and shown ayahs. A staged original-PCM/injected-word regression is written. | New-source native execution; no passing result is attributed before that run. |
| Page refits when microphone/input hint appears | Separate normal/live control reservations; concise hint uses existing header row. Original exact frame-equality UI assertion retained. | Actual current-source UI result; never weaken the equality assertion to hide a jump. |
| Slow or inaccurate first recognition | Capture is independent of ASR, bounded mailbox retains original input across cold preparation. Actual old GitHub independent warmup took25.81s; that is not an iPhone latency estimate. | Measure capture-to-first-word latency and error/abstention rate on held-out authorized, labeled learner speech. Cold-start/throughput success alone is insufficient. |
| All professional readers follow every word | Audit enumerates20readers ×114surahs =2280recordings with exact source hashes and negative controls. Development candidates remain separate from production. | Complete every recording, review actual word intervals, integrate approved exact recording/clock bindings and test app playback. No all-reader completion claim from partial machine candidates. |
| Repeatable test/build | Converter TLS roots verified; original float32 graph/weight pins unchanged. Exact one-byte auto conversion-date drift identified from original artifact; original edition date and actual regeneration timestamp now separate. Current672 bundled-asset gate passed. | Matching current native/acoustic/UI results. Normal reviewed-release gates remain unresolved; installed TestFlight24 is old. |

Current native receipt: `outputs/native-672-evidence/receipt.json` in the
workspace (not a committed test fixture), build6ad565d27550aed8108ff9e7,
source6722b451c9e2f81fbd4e9aad79d37c9c02301db0:18cases,0failures,
13.738s. Actual first-Allow UI failed after83.804s, RemoteIO RPC timeout.
The independent scoped acoustic check6ad5670b7550aed8108ffa06 is running;
its result has not been borrowed from another source.

GitHub run39182166954 atcb06ac2988148e5f9ea27f49c293488e0ee19f6e
is running the full live journey. Its app/tools/scripts/resources are identical
to672; only the workflow trigger paths changed. No new TestFlight upload is
claimed. Natural learner accuracy, Tajweed assessment, complete all-reader
word timings and complete product Release acceptance remain unestablished.
