#!/usr/bin/env bash
# Candidate experiment only: production byte pins/precision remain unchanged.
set -euo pipefail
export PYTHONHASHSEED=0
cd "$(dirname "$0")/.."
mkdir -p release/independent-mixed-coreml
python3 -m venv /tmp/noor-mixed-coreml-runtime
/tmp/noor-mixed-coreml-runtime/bin/python -m pip install --disable-pip-version-check \
 'torch==2.7.0' 'transformers==4.51.3' 'coremltools==9.0' \
 'numpy==2.1.3' 'safetensors==0.5.3'
python3 scripts/run-native-with-deadline.py 600 /tmp/noor-mixed-coreml-runtime/bin/python \
 tools/reciter_alignment/export_coreml.py --model "$HOME/.cache/noor-independent-ctc" \
 --output release/independent-mixed-coreml --precision mixed-normalization \
 2>&1 | tee release/independent-mixed-coreml/actual-log.txt
# No compile/bundle/pin update, source-based forced alignment or release pass.
