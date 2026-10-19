#!/usr/bin/env bash
# Development conversion/parity only: no signing, deployment, audio upload or app replacement.
set -euo pipefail
export PYTHONHASHSEED=0
cd "$(dirname "$0")/.."
mkdir -p release/independent-coreml
command -v python3.11 >/dev/null || brew install python@3.11
python3.11 -c "import sys;sys.path.insert(0,'scripts');from coreml_build_runtime import prepare;prepare('.', '/tmp/noor-coreml-py311-runtime')"
python3 scripts/run-native-with-deadline.py 480 /tmp/noor-coreml-py311-runtime/bin/python \
 tools/reciter_alignment/export_coreml.py --model "$HOME/.cache/noor-independent-ctc" \
 --output release/independent-coreml --precision float32 2>&1 | tee release/independent-coreml/actual-log.txt
python3 scripts/run-native-with-deadline.py 180 python3 scripts/verify-coreml-reproducibility.py \
 2>&1 | tee release/independent-coreml/reproducibility-log.txt
