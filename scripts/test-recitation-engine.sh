#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
  echo "This probe requires actual Apple Core ML execution; Linux results cannot replace it." >&2
  exit 1
fi
NOOR_PROBE_OUT="$(pwd)/release/recitation-engine-probe"
mkdir -p "$NOOR_PROBE_OUT"
python3 -m venv "$NOOR_PROBE_OUT/venv"
"$NOOR_PROBE_OUT/venv/bin/python" -m pip install 'huggingface-hub==1.33.0'
"$NOOR_PROBE_OUT/venv/bin/python" scripts/prepare-recitation-probe.py --output "$NOOR_PROBE_OUT/data"
swift run --package-path tools/RecitationEngineProbe -c release RecitationEngineProbe \
  "$NOOR_PROBE_OUT/data/model" "$NOOR_PROBE_OUT/data/tokenizer" \
  "$NOOR_PROBE_OUT/data/fixtures" "$NOOR_PROBE_OUT/coreml-investigation.json"
# Preserve both the raw evidence and its source hashes. This probe does not
# label a reader's mistakes or approve an iOS recitation feature.
