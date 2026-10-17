#!/usr/bin/env bash
set -euo pipefail
# Test an exact public source in a separate directory. No services, ports,
# credentials, package installations or production configuration are changed.
noor_source_commit="${1:?Pass the full reviewed commit SHA}"
[[ "$noor_source_commit" =~ ^[0-9a-f]{40}$ ]] || exit 2
for noor_dependency in git node python3 timeout; do
  command -v "$noor_dependency" >/dev/null || { echo "Missing dependency: $noor_dependency" >&2; exit 2; }
done
noor_quality_root=$(mktemp -d /tmp/noor-quality-XXXXXXXX)
mkdir -p "$noor_quality_root/temp"
export TMPDIR="$noor_quality_root/temp"
git clone --quiet --filter=blob:none --no-checkout --single-branch \
  --branch repair/noor-recitation-20261014 https://github.com/saud1596x/norAlroh.git "$noor_quality_root/source"
git -C "$noor_quality_root/source" checkout --quiet --detach "$noor_source_commit"
[[ "$(git -C "$noor_quality_root/source" rev-parse HEAD)" == "$noor_source_commit" ]] || exit 2
cd "$noor_quality_root/source"
python3 - "$noor_source_commit" "$noor_quality_root" <<'PY'
import json, platform, subprocess, sys
from pathlib import Path
Path(sys.argv[2], 'provenance.json').write_text(json.dumps({
    'sourceCommit': sys.argv[1], 'platform': platform.platform(),
    'node': subprocess.check_output(['node', '--version'], text=True).strip(),
    'python': platform.python_version(),
    'scope': 'Linux gateway and content/build helper tests only; not iOS or live microphone acceptance'
}, indent=2) + '\n')
PY
nice -n 10 timeout 180 node --max-old-space-size=256 --test server/quran-sync/worker.test.mjs \
  2>&1 | tee "$noor_quality_root/gateway-tests.log"
nice -n 10 timeout 180 python3 -m unittest discover -s scripts/tests -p 'test_*.py' -v \
  2>&1 | tee "$noor_quality_root/helper-tests.log"
printf 'Linux checks passed. Evidence retained at %s\n' "$noor_quality_root"
