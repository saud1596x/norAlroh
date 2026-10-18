# Acoustic discontinuities and preserved source evidence

This is a concrete engine repair, not calibrated learner-error or Tajweed
acceptance. The private cloud pilot is not connected to the shipping client.

## Reproduced defect

The server previously discarded low-confidence/invalid words, then aligned the
remaining array as one continuous phrase. For example, two short fragments
around a rejected source token could become a four-word canonical anchor that
the native local backend deliberately refuses. Source observations of those
rejected tokens were also lost. Four new policy regressions failed before the
repair (missing run/source fields and overlapping time accepted).

## Repair

- Keep explicit acoustic runs across rejected/no-speech/invalid-time tokens.
  Align each run independently; never connect two fragments by deleting doubt.
- Retain bounded ordered source observations, nullable unavailable timing and
  confidence, and the original unassessable state. No expected Quran word fills
  a rejected token. Non-finite backend values never reach JSON.
- Reject overlapping/reversed word timestamps as progress evidence.
- Native remote processing requires evidence-version2 readiness, verifies the
  accepted-word/source-observation identity and checks original PCM independently.
  Silent PCM cannot be accepted merely because the server reports confidence.
  Rejected source observations remain in the journal for reassessment.

## Actual local verification

`python -m pytest server/recitation/tests -q`: **36 passed,2 skipped**. The two
real-model cases require their explicit fixture environment and were not run by
this policy/transport suite. Four new tests reproduce rejection boundaries,
overlapping times, non-finite source values and no-speech segments.

Initial sandbox ASGI attempts stopped before application startup: a Python
thread sample showed Windows asyncio socketpair waiting in socket.accept. They
were cancelled, then the authorized localhost-capable run above completed.
This local environment restriction is not a server regression or passing test.

Both changed Swift files parse with tree-sitter; that is not native compilation.
`engine-boundary-check` is a separate bounded account-enabled Release/iPhone
regression for the new mapping and genuine public PCM cross-surah recognition.
No existing playback assertion, reviewed-preview or publication gate is removed
or marked successful. Its native result must be recorded after the actual run.

The two opt-in real-model tests were then run explicitly with the pinned CPU
model/public fixture environment: **2 passed in11.62s**. The continuous test also
checks that each accepted response word exactly matches its ordered source
observation. The real admission test still rejects the fifth connection and
allows only one actual inference; this is not a sustained-capacity claim.

The local existing RTX5060 comparison actually completed22 HTTP/WebSocket
cases, including ten known public clips at normal/3% volume and silence/noise.
Warm median latency0.250s/p950.375s, identical result replay22/22. No false
silence/noise location was emitted. WER0.0909 and standalone verse-location
rate0.4 describe only these reused clips/strict ambiguity abstentions, not unseen
learner quality. Internet/iPhone/cloud-GPU timing remains unmeasured. This run
loaded the evaluator before its additional source-identity assertion was added;
that assertion is separately exercised by the explicit real-model test above.

## Bundled backend follow-up

The same audit found that the bundled local word gate could accept a timestamp
up to100ms beyond its captured window and did not reject a word overlapping the
previous decoded word. It also discarded all source words of a no-speech
segment. The follow-up extracts a tested local accumulator: preserve uncertain
source text, keep valid nullable source times and reject overlaps/out-of-window
times as progress. It changes neither recorded PCM nor Quran display text.
Three new policy cases plus genuine public PCM recognition are required in the
subsequent native run before attributing any pass to this bundled-backend change.

Actual [first native run](https://codemagic.io/app/6ac3b8b756235b59ec04e90a/build/6ad423d57550aed8108fb91a)
on293dd5c passed23selected tests,0failures/testExit0 in9m20s. The real two-clip
continuous recognition case passed in11.975s; this is injected public PCM, not a
physical microphone. Actual [bundled follow-up](https://codemagic.io/app/6ac3b8b756235b59ec04e90a/build/6ad426947550aed8108fb984)
on89e90e4 (app runtime8cdd7f1) passed26selected tests,0failures/testExit0 in9m17s.
Both used account-enabled Release/Xcode26.3/iOS26.2/iPhone17Pro Simulator. Their
scope still excludes speaker preparation, device microphone and full release.

## Routing/clock follow-up before enabling remote inference

Source review found the router advertised the configured preference rather
than the provider actually leased by the current take. A preference change
could label a local result as remote. The follow-up publishes a lock-protected
actual-provider snapshot, applies remote opt-in on the next take, immediately
stops remote decoding on revocation, and discards results of ended generations.

An exact clock counterexample also exists: baseFrame2/startFrame29 makes
`streamTime + baseTime - windowTime` negative for an actual zero-offset word.
Subtracting the stream origin first avoids this reassociation error; absolute
stream bounds still reject timestamps outside captured PCM. Source timestamps
are not interpolated and no reference word replaces an acoustic observation.

Three additional native regressions cover the source switch, revocation and
fractional-frame clock. Their native result is PENDING; the26-test result above
must not be attributed to this follow-up. The remote origin remains unconfigured
in the app; cloud TLS/identity/E2E and GPU quota are still prerequisites.

The known AVAudioPlayer.prepareToPlay/HAL timeout remains unresolved playback
acceptance. The focused engine workflow does not claim to resolve that timeout,
physical microphone behavior, remote iPhone/server E2E, all-reciter word timing,
full Release coverage or a production deployment.

GPU quota ticket12918189 remains Open with no support reply at the current
read. No DigitalOcean trial resource exists and cloud-trial spend remains zero.
The authorized trial ceiling is USD3/two hours, separate from native CI. Payment
or CI authorization does not authorize an indefinite monthly GPU deployment.
