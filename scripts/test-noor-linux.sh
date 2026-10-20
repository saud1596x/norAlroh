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
# A reviewed verification-branch SHA may not be reachable from the historical
# repair branch. Fetch that exact source, never silently fall back to its tip.
git -C "$noor_quality_root/source" fetch --quiet --depth 1 origin "$noor_source_commit"
git -C "$noor_quality_root/source" checkout --quiet --detach "$noor_source_commit"
[[ "$(git -C "$noor_quality_root/source" rev-parse HEAD)" == "$noor_source_commit" ]] || exit 2
cd "$noor_quality_root/source"
python3 - <<'PY'
import importlib.metadata
from pathlib import Path

pins = [line.strip() for line in Path('scripts/tests/requirements.txt').read_text(encoding='utf-8').splitlines()
        if line.strip() and not line.lstrip().startswith('#')]
for pin in pins:
    name, separator, required = pin.partition('==')
    if not separator or not name or not required:
        raise SystemExit('Invalid shared helper test dependency declaration; no packages installed.')
    try:
        actual = importlib.metadata.version(name)
    except importlib.metadata.PackageNotFoundError:
        raise SystemExit(f'Missing prerequisite: {pin}. This server check does not install packages.')
    if actual != required:
        raise SystemExit(f'Prerequisite mismatch: {name} requires {required}, found {actual}. No packages installed.')
from PIL import Image
print('Shared helper test prerequisites are present; no packages installed.')
PY
python3 - "$noor_source_commit" "$noor_quality_root" <<'PY'
import importlib.metadata, json, platform, subprocess, sys
from pathlib import Path
Path(sys.argv[2], 'provenance.json').write_text(json.dumps({
    'sourceCommit': sys.argv[1], 'platform': platform.platform(),
    'node': subprocess.check_output(['node', '--version'], text=True).strip(),
    'python': platform.python_version(),
    'helperTestDependencies': {'Pillow': importlib.metadata.version('Pillow')},
    'scope': 'Linux gateway and content/build helper tests only; not iOS or live microphone acceptance'
}, indent=2) + '\n')
PY
nice -n 10 timeout 180 node --max-old-space-size=256 --test server/quran-sync/worker.test.mjs \
  2>&1 | tee "$noor_quality_root/gateway-tests.log"
nice -n 10 timeout 180 python3 -m unittest discover -s scripts/tests -p 'test_*.py' -v \
  2>&1 | tee "$noor_quality_root/helper-tests.log"
printf 'Linux checks passed. Evidence retained at %s\n' "$noor_quality_root"
