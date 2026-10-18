# Staging and exact-recording timing evidence — 18 October 2026

This is progress evidence, not product acceptance or a publication approval.

## Private CPU service

The first installed source archive
`bb1dc5a4ad7175e165c5134037172006cc2f323bf6cc827e46e189058e3ba151`
built successfully but its unprivileged application could not import
`noor_engine.api`. The actual diagnostic file showed restart/exit3, not OOM.
The installer had used root umask077 for source directories; Docker COPY
preserved those modes and UID10001 could not traverse them.

Commit003fcb9 explicitly sets only extracted image-source directories0755 and
source files0644. Root runtime.env and the installation root remain private.
An unprivileged, network-isolated import probe must succeed before replacing
the API container. The old container is stopped and retained under its backup
name; the same data volume, key, model and exact source archive are preserved.
No Roleva service, proxy, firewall, account permission or public port changed.

The user's root-console photo actually shows `NOOR_IMAGE_IMPORT_OK`, image
`noor-recitation-staging:bb1dc5a4ad71-importfix1`, and
`NOOR_PRIVATE_STAGING_READY` with `ready:true`. This proves private loopback
startup and pinned model loading. It does not prove recognition latency,
Firebase authentication from the app, HTTPS deployment, production PostgreSQL,
learner accuracy or TestFlight integration.

Four local payload/isolation tests passed; a Unix mode regression was added
but skipped on Windows. Its result is not represented as a Linux test pass.
The independent operator-run public-audio probe is in
`server/recitation/verify_private_staging.py`. It uses a separate bounded
network-none temporary container with no service credentials/database mounts.
The operator actually ran it successfully (exit0,39.47s including startup,
model/corpus load and three inferences). The API remained ready before/after.
Three hash-verified public clips yielded their observed words. The four-word
112:1 and114:1 clips located correctly; standalone two-word112:2 abstained.
Silence yielded no words. Single-thread CPU inference times were12.225,8.795
and11.441 seconds for3.135,2.821 and5.042 seconds of audio. These measurements
are from the one-core,1024MiB isolated probe, not concurrent production API
or iPhone timings. They do not meet an immediate-feedback latency target.
The stderr warning about an unwritable ONNX telemetry device-ID cache fell
back to an in-memory identifier; the actual inference process exited0.

The service shares an existing host with Roleva, although its process/files/
database/listener are separate. A dedicated host was not purchased: the user's
USD10 authorization covers iOS attempts, not recurring infrastructure. No
public TLS route or app origin was introduced. A new host alone is not a
measured acoustic/latency improvement.

## Actual iOS repair run

[Codemagic6ad417637550aed8108fb740](https://codemagic.io/app/6ac3b8b756235b59ec04e90a/build/6ad417637550aed8108fb740)
tested sourcebf8aed1, account-enabled Release, Xcode26.3/iOS26.2/iPhone17Pro.
Compilation succeeded;25 unique test cases passed and one timed out. Overall
testExit65 / FAILED. The repaired ambiguous-short-anchor regression passed.

The genuine public-PCM session reached pause.end, restore.begin, resume.begin
and finish.end. Its actual AVAudioFile frame count assertion completed before
`audio.prepare.begin`; `audio.prepare.end` never appeared. The second real
thread sample contains AVAudioPlayer.prepareToPlay → AudioQueuePrime →
AQMEIO_HAL → HALC_ProxyIOContext::_TellServerAboutStreamUsage. This locates this
timeout in playback preparation, not in the preceding recognition drain. It
does not establish that every playback failure is provider-only, or that
physical-device playback/microphone works. The original assertion and failed
result are retained. No identical paid retry was started.

Actual UI/all604 checks were not repeated by this focused run. The earlier
5a16 run passed its UI/all604 checks but failed two unit conditions; do not
label it overall successful. No new TestFlight build was started here.

## Professional reciter word timing

Commitc56afc8 adds an offline evaluator for exact catalog audio, pinned Quran
CTC weights/config/vocabulary, native-ID binding, silence/noise/wrong-text
controls and whole-recording coverage validation. It does not assess learners
or modify Quran display text. Seven local algorithm/asset tests passed.

An actual bounded local CPU pass processed20 catalog recordings for each of
surahs1/112/113/114:18/19/16/16 whole-recording candidates, respectively. All
69 candidate native-ID sequences match the pinned canonical snapshot;11
recordings were rejected. Negative controls rejected for every tested surah.
Candidates are not human-reviewed, shipped resources or app playback proof.

Full2280-track coverage, weak-word/boundary review, long-surah/isolated-letter
evaluation and exact-recording runtime integration remain incomplete. Existing
app full-surah metadata is ayah timing, not proof of word timing for all20
readers. Unknown intervals must not be interpolated or presented as verified.

Operational receipts, complete local reports and actual sampled log text are
under the outer workspace `outputs/`; they contain no private microphone audio.
