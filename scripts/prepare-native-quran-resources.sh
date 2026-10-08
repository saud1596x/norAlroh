#!/usr/bin/env bash
# Every native app generation includes the same verified reading and recognition
# resources. A unit-test-only workflow must not produce an unusable reader.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/prepare-qcf-v2.py --output ios/Athar/Fonts
python3 scripts/prepare-mushaf-companion.py
cp release/qcf-v2-manifest.json ios/Athar/qcf-v2-manifest.json
python3 scripts/prepare-recitation-model.py
