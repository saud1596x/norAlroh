#!/usr/bin/env bash
# Every native app generation includes the same verified reading and recognition
# resources. A unit-test-only workflow must not produce an unusable reader.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v python3.11 >/dev/null || brew install python@3.11
python3 scripts/prepare-bundled-mushaf.py
python3 scripts/prepare-qcf-v2.py --output ios/Athar/Fonts
python3 scripts/prepare-mushaf-companion.py
cp release/qcf-v2-manifest.json ios/Athar/qcf-v2-manifest.json
python3 scripts/prepare-tajweed-fonts.py --output ios/Athar/Fonts/Tajweed
cp release/qcf-v4-manifest.json ios/Athar/qcf-v4-manifest.json
python3 scripts/prepare-recitation-model.py
python3 scripts/prepare-independent-ctc.py
