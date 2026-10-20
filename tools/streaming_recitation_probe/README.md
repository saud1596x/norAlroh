# Public source screening and evidence integrity

This is an offline FP32 source experiment, not a streaming engine, iPhone test,
learner evaluation, release gate, or model promotion. Empty or inaccurate raw
transcripts remain unchanged in the report. Completing the experiment verifies
execution only; it does not assert recognition quality or negative-control success.

Run 39313997335 is **not inference evidence**. Its `av==14.4.0` source build failed
before the runtime was installed, and the subsequent probe failed at importing
`yaml`. Piping the commands to `tee` concealed the producer failure. Do not reuse
that run's green workflow status as a successful model result.

## Install contract

The workflow uses Python 3.11 on standard Ubuntu 24.04. PyAV 14.4.0 has no matching
official Linux CPython 3.11 wheel. PyAV 14.2.0 provides the compatible
`cp311-cp311-manylinux_2_17_x86_64.manylinux2014_x86_64` wheel. Its SHA-256 is pinned
in `requirements-audio-linux.txt`, and `--only-binary=:all: --require-hashes` makes
an unavailable or different wheel fail before model work. Official metadata:
<https://pypi.org/pypi/av/14.2.0/json>.

Every shell step uses `set -euo pipefail`, including dependency install logs.
`pip check` and actual runtime imports must succeed before decoding. The model
archive and configuration remain hash pinned; tensor restoration still requires
`torch.load(..., weights_only=True)` and the known NeMo class.

## Execution contract

`run_probe.py` logs the child directly without a success-masking `tee` pipeline.
It removes only four named previous evidence files in its output directory,
preserves a nonzero producer exit code, and writes an execution receipt on failure.
Even a zero exit fails unless `validate_result.py` verifies:

- The current full source commit and pinned model/configuration identity.
- Completed inference, precisely 26 unique ordered input cases, and positive
  encoder outputs and finite inference durations.
- Valid raw CTC tokens, original PCM frame counts and hashes, source MP3 pins,
  and exactly the same 26 raw rows in the producer log.
- A single completion marker and explicit non-approval flags.

The validated receipt never grants production, learner accuracy, streaming, or
iPhone acceptance. Synthetic unit-test reports are created in a separate temporary
test directory, never uploaded as model results.

```sh
python -m unittest discover -s tools/streaming_recitation_probe/tests -v
python tools/streaming_recitation_probe/run_probe.py \
  --output-dir release/fastconformer-source-probe \
  --expected-commit "$(git rev-parse HEAD)" -- \
  timeout 480s python -u tools/streaming_recitation_probe/verify_source.py
```

Regressions cover a deliberate child failure after writing a complete report,
zero cases despite exit zero, absent/corrupt/partial/duplicated evidence, a stale
commit or report, malformed output, and pipeline failure. The Bash regression
runs on Ubuntu and is explicitly skipped when Bash is absent on Windows.
