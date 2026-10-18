# Noor recitation service

Implemented local service, **not deployed staging or production**. Existing
Apple/Firebase login and local iPhone recognition are preserved. No service URL
or remote consent is enabled in the current app bundle. The604-page edition
is preserved; this service binds the pinned77,429 native
word IDs across6,236 ayahs, never supplies display text.

## Responsibilities and boundaries

One FastAPI service: identity validation → opaque rotated credentials → bounded
session/WebSocket transport → actual pinned ASR → exact whole-corpus native
alignment → provisional differences → encrypted recovery state. No Redis,
external speech API, recording bucket, GPU cluster or billing setup. One service
process / one inference worker / four active session slots. This is an initial
capacity configuration, **not a measured four-way inference capacity claim**.

Recognition uses the existing Quran-adapted third-party model
`OdyAsh/faster-whisper-base-ar-quran` at
`8578bafd427d122f671b187706650e76edf6f86f`, CTranslate2 and Silero VAD.
CPU int8 remains the default. Explicit `NOOR_INFERENCE_DEVICE=cuda` uses float16
on an existing compatible NVIDIA host; startup compiles kernels using discarded
silent input before readiness. This artificial warmup is never quality evidence.
It requires official CUDA12 cuBLAS and cuDNN9 runtime libraries. The default
CPU-only Docker image does not include those libraries or reserve a GPU. There
is no automatic GPU purchase, device fallback or deployment claim.
The project owns orchestration, contracts, native binding, ambiguity policy and
session recovery; it does not claim to have trained or own these model weights.
Publisher-declared Apache2 notice and upstream project notices remain in docs.
`model-manifest.json` pins every runtime-required asset. Runtime never downloads
or substitutes another tokenizer/model. Do not rename a generic model to claim
Quran specialization. Calibration and acoustic Tajweed assessment are unsupported.

## Run and verify locally

Use Python3.12, an isolated environment, and `pip install -r requirements.txt`.
Install `pytest==9.1.1` for tests. Provide the pinned model folder; the existing
`tools/LinuxRecitationBenchmark/benchmark.py` documents obtaining the CPU assets
and independently verified tokenizer. All model files must match the manifest.
Set `PYTHONPATH=server/recitation`, `NOOR_CORPUS_ROOT` to the repository root,
`NOOR_MODEL_PATH` to that directory, a private `NOOR_DATA_KEY`,
`NOOR_ENVIRONMENT=local`, and a local SQLite `NOOR_DATABASE_URL`. Then:

```sh
python -m pytest server/recitation/tests -q
python -m uvicorn noor_engine.api:application --factory --host 127.0.0.1 --port 8080 --workers 1 --ws-max-size 524288 --ws-max-queue 1 --no-access-log
python server/recitation/evaluate.py --corpus-root "$PWD" --model /verified/model --fixtures /verified/public-fixtures --output /local/evidence
```

The evaluator uses real loopback TCP/WebSocket and real model inference. It only
creates a temporary **local-test** principal, does not bypass shipped runtime
identity validation, does not upload user recordings and does not create cloud
keys. The ten public fixtures have already been used in earlier diagnostics;
they are not an unseen test set. Do not publish their WER as general learner
accuracy. Artificial fault-policy fixtures are labeled separately from real ASR.

## Protocol

OpenAPI: `GET /openapi.json`. Health: `/health/live`, `/health/ready` (503 if
assets/model/database are unavailable). Client first authenticates using an
Apple-origin Firebase ID token via `POST /v1/auth/firebase`, or obtains a one-use
nonce with `/v1/auth/apple/challenge` and validates an Apple identity token with
`/v1/auth/apple`. Issuer, audience, RS256, pinned JWKS destination, expiry and
nonce are checked. Firebase `sign_in_provider` must be `apple.com`; no credential
is trusted from decoding JWT without verification. JWKS tests use explicit local
cryptographic test keys; real Apple/Firebase network login is not yet exercised.

Access lifetime15min, refresh30days, opaque credentials are hashed. Refresh
rotation invalidates the prior access credential; replay revokes the entire
family. Identity deletion revokes all credentials and session data. A minimal
HMAC deletion marker for31days blocks stale identities from restoring access
without a newer real authentication. No email/profile is stored.

`POST /v1/sessions` requires consent
`transient-audio-encrypted-recovery-1h`. No audio retention option is implemented:
samples only exist in bounded inference memory. Derived results/state are
encrypted for at most1hour, purged everyminute and on explicit close, and never
logged. Close deletes them immediately. Logs include numeric latency/status and
random request ID only. No query, bearer token, transcript, location or user ID.

Connect `/v1/sessions/{id}/audio` with Authorization header (never URL token).
One JSON header `{sequence,start_frame,end_frame}` followed by binary mono16kHz
float32 little-endian PCM. At most128,000samples/8seconds per window, one in
flight, continuous monotonically increasing end frames; overlapping windows
are allowed. NaN/clipped/out-of-order/gap/mismatched replay are rejected. Initial
sequence0 starts at frame0. Silence windows still preserve sequence continuity.
On reconnect resend the exact unacknowledged header+bytes: a committed sequence
returns the identical encrypted cached result. Different bytes for the same
sequence fail. Owner-authenticated GET returns next sequence/recovery state.

Events carry source model/edition, session, sequence, frame boundaries and
monotonic event IDs. Revisions replace covered evidence and retract provisional
differences. A word event means exact acoustic-token location evidence, never
verified pronunciation. No `ERROR_CONFIRMED` or Tajweed success is emitted from
uncalibrated ASR text. A pause/shared phrase yields uncertainty, not a mistake.
The native client validates events transactionally then passes source words
through its independent acoustic gate, tracker and durable local journal.

Word evidence version2 adds ordered source observations (including rejected
tokens with nullable timing/confidence) and explicit acoustic run indices.
Rejected/no-speech/overlapping-timestamp tokens break a run; their two neighbors
cannot form an artificial contiguous anchor. The native client requires version2
readiness, verifies accepted source identity, rechecks actual PCM independently
and retains unassessable observations without awarding progress. Existing local
capture and approved Mushaf appearance are unaffected. This is a contract/policy
repair, not a claim of calibrated ASR or physical-device verification.

## Staging operations / remaining blockers

`compose.yaml` builds from repository root, binds port8080 to loopback only and
requires an existing certificate-verified PostgreSQL URL and protected external
key. It creates no cloud service/account/key and does not publish a listener to
the internet. Put an authorized TLS reverse proxy in front with body/frame limits,
WS idle timeout≥45s and a global IP abuse guard. Disable proxy access logs or
redact all credentials. Do not trust arbitrary forwarded-IP headers. No browser
Origin or arbitrary CORS audience is accepted by the native socket.

The SQLAlchemy v1 schema is created explicitly at startup; incompatible versions
fail closed. Before an upgrade, take an encrypted PostgreSQL backup and exercise
restore into a separate staging database, including schema-version validation.
Keep the encryption key in the secret manager, separate from backup data. Key
rotation currently invalidates transient identity/recovery state: drain sessions,
purge expired derived state and credentials, rotate, require new login. Do not
rotate in place and promise seamless recovery. The service owns no reading data;
Firebase continues to own opt-in reading sync. Future schema changes require a
versioned migration, rollback plan and PostgreSQL migration tests.

Health refuses readiness/new sessions while an overdue decode still holds the
real compute lease. Atomic conditional database upserts enforce rate limits even
when the first requests arrive concurrently; an absent row cannot be SELECT-locked.
Health and authenticated numeric metrics cover inference completion/timeouts,
replays/rejections and active connections. Set alerts on readiness failure,
sustained engine-busy responses and timeout ratio. An uncooperative SDK decode
retains the real worker lease until it exits; it never permits overlapping work
after a timeout. Production must use one Uvicorn process until distributed
admission/connection leases exist. Do not add replicas and claim linear scaling.

Actual staging host/TLS/database/secret access, Docker build, PostgreSQL restore,
real Apple network validation, native client-to-staging build and device latency
are **not verified**. No production deployment is claimed. Configuring
`NoorRecitationServerURL` requires updated privacy disclosures/consent and Apple
privacy questionnaire review before distributing that remote-enabled build.
Without the URL the native app stays fully local; no hidden fallback upload.
