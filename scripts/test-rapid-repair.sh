#!/usr/bin/env bash
# Fast diagnosis of the current failures. This is not the Release publication gate.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p release/rapid-repair
python3 scripts/select-xcode.py > release/rapid-repair/xcode.env
source release/rapid-repair/xcode.env
export DEVELOPER_DIR
python3 - <<'PY'
import json,subprocess,time
from pathlib import Path
Path('release/rapid-repair/context.json').write_text(json.dumps({
    'sourceCommit':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),
    'startedUnix':time.time(),'configuration':'Debug',
    'scope':'Targeted failure reproduction; not complete Release, voice accuracy or physical device acceptance'
},indent=2)+'\n')
PY
xcodegen generate --spec ios/project.yml --project ios
device=$(python3 - <<'PY'
import json,subprocess
devices=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','--json']))
phones=[d for runtime,rows in devices['devices'].items() if 'SimRuntime.iOS' in runtime for d in rows
        if d.get('isAvailable') and d['name'].startswith('iPhone') and 'Pro Max' not in d['name']]
assert phones,'An iPhone Simulator is required'
print(phones[0]['udid'])
PY
)
state=$(xcrun simctl list devices available --json | python3 -c 'import json,sys; print(next(x["state"] for rows in json.load(sys.stdin)["devices"].values() for x in rows if x["udid"]==sys.argv[1]))' "$device")
if [[ "$state" != Booted ]]; then xcrun simctl boot "$device"; fi
xcrun simctl bootstatus "$device" -b
common=(-project ios/Athar.xcodeproj -scheme Athar -configuration Debug
  -destination "platform=iOS Simulator,id=$device"
  -derivedDataPath release/rapid-derived-data CODE_SIGNING_ALLOWED=NO
  ENABLE_TESTABILITY=YES ONLY_ACTIVE_ARCH=YES -parallel-testing-enabled NO
  'OTHER_SWIFT_FLAGS=$(inherited) -DNOOR_ACCEPTANCE_TESTING')
xcodebuild build-for-testing "${common[@]}"
# Run the exact failing walkthrough first, without waiting for unrelated unit
# suites or a second physical-device archive. Keep its original assertions.
navigation_exit=0
xcrun simctl privacy "$device" reset microphone com.saud1596x.nooralruh
xcodebuild test-without-building "${common[@]}" \
  -only-testing:AtharUITests/NoorAllScreensTests/testAllScreensWalkthrough \
  -resultBundlePath release/rapid-repair/navigation.xcresult || navigation_exit=$?
microphone_exit=0
xcrun simctl privacy "$device" grant microphone com.saud1596x.nooralruh
xcodebuild test-without-building "${common[@]}" \
  -only-testing:AtharUITests/NoorMushafStudyUITests \
  -resultBundlePath release/rapid-repair/microphone.xcresult || microphone_exit=$?
python3 - "$navigation_exit" "$microphone_exit" <<'PY'
import json,sys,time
from pathlib import Path
p=Path('release/rapid-repair/context.json'); data=json.loads(p.read_text())
data.update(finishedUnix=time.time(),navigationExit=int(sys.argv[1]),microphoneExit=int(sys.argv[2]))
data['elapsedSeconds']=data['finishedUnix']-data['startedUnix']
p.write_text(json.dumps(data,indent=2)+'\n')
PY
[[ "$navigation_exit" == 0 && "$microphone_exit" == 0 ]]
