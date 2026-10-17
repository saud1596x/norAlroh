#!/usr/bin/env bash
# Diagnostic only. Never replaces Noor's real audio or Release acceptance gates.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p release/isolated-audio
python3 scripts/select-xcode.py > release/isolated-audio/xcode.env
source release/isolated-audio/xcode.env
export DEVELOPER_DIR
xcodegen generate --spec tools/StandaloneAudioProbe/project.yml --project tools/StandaloneAudioProbe
if [[ -n "${CM_BUILD_ID:-}" ]]; then
  # Keep the previous worker preparation constant; change only the test host.
  sudo -n killall coreaudiod || true
  sleep 2
  python3 - <<'PY'
import subprocess,time
started=time.monotonic()
try:
    result=subprocess.run(['/usr/bin/afplay','ios/AtharTests/RecitationFixtures/112001.mp3'],capture_output=True,text=True,timeout=10)
    print('ISOLATED_HOST_AFPLAY',result.returncode,'seconds',time.monotonic()-started,result.stderr[-500:])
except subprocess.TimeoutExpired:
    print('ISOLATED_HOST_AFPLAY timeout')
PY
fi
device=$(python3 - <<'PY'
import json, subprocess, hashlib, time
from pathlib import Path
runtime='com.apple.CoreSimulator.SimRuntime.iOS-26-2'
devices=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','--json']))
phones=[d for d in devices['devices'].get(runtime,[]) if d.get('isAvailable') and d['name']=='iPhone 17 Pro']
assert phones, 'The exact iOS26.2 iPhone17Pro comparison runtime is required'
p=phones[0]
context={'sourceCommit':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),
  'runtime':runtime,'device':p['name'],'udid':p['udid'],'startedUnix':time.time(),
  'fixtureSHA256':hashlib.sha256(Path('ios/AtharTests/RecitationFixtures/112001.mp3').read_bytes()).hexdigest(),
  'scope':'Only independent AVFoundation playback test host; no Noor engine or microphone acceptance'}
Path('release/isolated-audio/context.json').write_text(json.dumps(context,indent=2)+'\n')
print(p['udid'])
PY
)
cat release/isolated-audio/context.json
state=$(xcrun simctl list devices available --json | python3 -c 'import json,sys; print(next(x["state"] for rows in json.load(sys.stdin)["devices"].values() for x in rows if x["udid"]==sys.argv[1]))' "$device")
if [[ "$state" != Booted ]]; then xcrun simctl boot "$device"; fi
xcrun simctl bootstatus "$device" -b
open -a Simulator --args -CurrentDeviceUDID "$device"
system_profiler SPAudioDataType -json > release/isolated-audio/host-audio.json
audio_exit=0
xcodebuild test -project tools/StandaloneAudioProbe/StandaloneAudioProbe.xcodeproj \
  -scheme AudioProbe -configuration Debug -destination "platform=iOS Simulator,id=$device" \
  -derivedDataPath release/isolated-audio-derived CODE_SIGNING_ALLOWED=NO \
  -parallel-testing-enabled NO -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 60 -maximum-test-execution-time-allowance 90 \
  -resultBundlePath release/isolated-audio/actual-playback.xcresult || audio_exit=$?
python3 - "$audio_exit" <<'PY'
import json,sys,time
from pathlib import Path
p=Path('release/isolated-audio/context.json');d=json.loads(p.read_text())
d.update(exitCode=int(sys.argv[1]),finishedUnix=time.time())
p.write_text(json.dumps(d,indent=2)+'\n')
print('ISOLATED_AUDIO_RESULT', json.dumps(d))
PY
exit "$audio_exit"
