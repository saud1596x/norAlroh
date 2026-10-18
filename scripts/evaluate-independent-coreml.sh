#!/usr/bin/env bash
# Development conversion/parity only: no signing, deployment, audio upload or app replacement.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p release/independent-coreml
python3 -m venv /tmp/noor-coreml-runtime
/tmp/noor-coreml-runtime/bin/python -m pip install --disable-pip-version-check \
 'torch==2.7.0' 'transformers==4.51.3' 'coremltools==9.0' \
 'numpy==2.1.3' 'safetensors==0.5.3'
python3 scripts/run-native-with-deadline.py 480 /tmp/noor-coreml-runtime/bin/python \
 tools/reciter_alignment/export_coreml.py --model "$HOME/.cache/noor-independent-ctc" \
 --output release/independent-coreml 2>&1 | tee release/independent-coreml/actual-log.txt
