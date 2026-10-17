#!/usr/bin/env bash
# Continuous recognition, canonical alignment and native reader regressions; not full release acceptance.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p release/continuous-reader
xcodegen generate --spec ios/project.yml --project ios
device=$(python3 - <<'PY'
import json,subprocess
from pathlib import Path
runtime='com.apple.CoreSimulator.SimRuntime.iOS-26-2'
devices=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','--json']))
phones=[d for d in devices['devices'].get(runtime,[]) if d.get('isAvailable') and d['name']=='iPhone 17 Pro']
assert phones,'Exact iOS26.2/iPhone17Pro runtime is required'
phone=phones[0]
Path('release/continuous-reader/context.json').write_text(json.dumps({
  'sourceCommit':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),
  'xcode':subprocess.check_output(['xcodebuild','-version'],text=True).strip(),
  'runtime':runtime,'device':phone['name'],'configuration':'Release',
  'scope':'All604 native canvas rendering, reciter identity/search, public PCM continuous cross-surah recognition, VAD; not device microphone or calibrated error/Tajweed acceptance'
},indent=2)+'\n')
print(phone['udid'])
PY
)
cat release/continuous-reader/context.json
state=$(xcrun simctl list devices available --json | python3 -c 'import json,sys; print(next(d["state"] for rows in json.load(sys.stdin)["devices"].values() for d in rows if d["udid"]==sys.argv[1]))' "$device")
if [[ "$state" != Booted ]]; then xcrun simctl boot "$device"; fi
xcrun simctl bootstatus "$device" -b
test_exit=0
xcodebuild test -project ios/Athar.xcodeproj -scheme Athar -configuration Release \
  -destination "platform=iOS Simulator,id=$device" \
  -derivedDataPath release/continuous-reader-derived-data CODE_SIGNING_ALLOWED=NO \
  ENABLE_TESTABILITY=YES ONLY_ACTIVE_ARCH=YES -parallel-testing-enabled NO \
  'OTHER_SWIFT_FLAGS=$(inherited) -DNOOR_ACCEPTANCE_TESTING' \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 60 \
  -maximum-test-execution-time-allowance 180 \
  -only-testing:AtharTests/NoorContinuousMushafTests \
  -only-testing:AtharTests/QuranWordAlignmentTests \
  -only-testing:AtharTests/QuranRecognitionWorkerLifecycleTests \
  -only-testing:AtharTests/QuranRecognitionCapabilityTests \
  -only-testing:AtharTests/MushafViewportTests \
  -only-testing:AtharTests/QuranWindowMailboxTests \
  -only-testing:AtharUITests/NoorContinuousReaderUITests \
  -resultBundlePath release/continuous-reader/actual-tests.xcresult || test_exit=$?
python3 - "$test_exit" <<'PY'
import json,sys
from pathlib import Path
p=Path('release/continuous-reader/context.json');data=json.loads(p.read_text())
data['testExit']=int(sys.argv[1]);p.write_text(json.dumps(data,indent=2)+'\n')
print('CONTINUOUS_READER_RESULT',json.dumps(data))
PY
exit "$test_exit"
