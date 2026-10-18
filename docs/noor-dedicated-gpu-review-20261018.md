# Dedicated Noor inference candidate — cost and verification review

This document authorizes no purchase, quota request, credential, public endpoint
or recurring deployment. The account's actual create page currently states:
"You don't have access to Droplet GPUs" and disables creation. No resource was
created and no access request was submitted.

## Selected initial comparison

One NVIDIA RTX4000 Ada,20GB VRAM,8vCPU,32GB RAM,500GB boot disk, Toronto TOR1.
This is a bounded single-GPU inference experiment, not a capacity commitment.
The choice is an engineering candidate: existing local CUDA tests are promising,
but do not establish cloud GPU, internet, iPhone or concurrent-user performance.

Sources checked18October2026:

- [DigitalOcean GPU pricing](https://www.digitalocean.com/pricing/gpu-droplets):
  RTX4000 Ada is USD0.76/hour on demand. Two hours compute USD1.52 before tax;
  continuous30-day operation720hours is USD547.20 before tax. This is a compute
  estimate, not an all-in service quotation or monthly cap. GPU billing continues
  while powered off; destruction is required to end reserved-resource charges.
- [GPU regional availability](https://docs.digitalocean.com/products/droplets/details/gpu-availability/):
  this model is offered in TOR1. Account quota and actual capacity are separate.
  Toronto network latency must be measured from the user's region.
- [faster-whisper1.2.1 requirements](https://github.com/SYSTRAN/faster-whisper/tree/v1.2.1):
  CUDA12 cuBLAS and cuDNN9; Linux NVIDIA pip libraries are a supported method.

Suggested first spending request, if proceeding: at mostUSD3 total for a
two-hour comparison including taxes/rounding buffer, with no continued monthly
operation approved. Do not substitute another more expensive plan automatically.
No extra database, storage, backup, domain or subscription is included. Access
setup and public deployment require review separately; an existing Roleva key
must not be reused silently. A disposable benchmark may contain only pinned
models and public clips so its removal does not discard user data. Stopping a
VM is not a spending stop; teardown must be planned before creating it.

## Prepared implementation

`server/recitation/Dockerfile.gpu` retains the pinned CPU service/corpus and adds
hash-pinned Linux CUDA libraries matching versions used in the actual local
CUDA experiment. The additional dependency closure includes NVRTC. The image
uses UID10001, checks module and library imports at build, defaults explicitly
to CUDA, and does not silently fall back to CPU on missing GPU.

No CUDA wheels were downloaded/installed locally in this step; only official
PyPI metadata and hashes were retrieved. Linux Docker build, NVIDIA driver
compatibility, runtime kernels and cloud inference are NOT VERIFIED. The
existing working CPU pilot and its current image are untouched.

## Measurement before any permanent decision

1. Verify the dedicated GPU/driver actually exposed to the container. One
   process, pinned model bytes/revision, no expected-text prompt for learner ASR.
2. Repeat the exact public PCM controls used for the CPU/local GPU comparisons:
   normal/quiet clips, silence, noise, ambiguous short phrases and transitions.
   Preserve rejected/uncertain results rather than treating confidence as a score.
3. Record cold load and warm p50/p95, CPU/GPU/RAM, model/configuration, audio
   duration and all failures. An initial warm p95 below1second is a target,
   not an achieved result or internet/SLA promise. Enforce actual admission
   limits and replay/owner boundaries before any concurrency claim.
4. Keep network-only latency and iPhone capture-to-visible-word latency separate.
   Test authentic learner speech before claiming accuracy. Faster hardware does
   not establish word-error, mistake-detection or Tajweed quality.
5. Review cost/result before a recurring deployment. TLS, database backup/restore,
   identity verification, consent/privacy and the actual native client journey
   remain release prerequisites. All-reader word following is a separate exact-
   recording data requirement; a GPU VM does not complete2280 tracks by itself.
