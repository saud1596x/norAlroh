#!/usr/bin/env bash
# A new file-preservation regression, not a substitute for real playback gates.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p release/recording-preservation
xcodegen generate --spec ios/project.yml --project ios
device=$(python3 - <<'PY'
import json,subprocess
from pathlib import Path
runtime='com.apple.CoreSimulator.SimRuntime.iOS-26-2'
devices=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','--json']))
phones=[d for d in devices['devices'].get(runtime,[]) if d.get('isAvailable') and d['name']=='iPhone 17 Pro']
assert phones,'Exact iOS26.2/iPhone17Pro runtime is required'
phone=phones[0]
Path('release/recording-preservation/context.json').write_text(json.dumps({
  'sourceCommit':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),
  'xcode':subprocess.check_output(['xcodebuild','-version'],text=True).strip(),
  'runtime':runtime,'device':phone['name'],'configuration':'Debug',
  'scope':'Archive write-failure recovery and session ownership only; not actual playback, microphone, recognition or release acceptance'
},indent=2)+'\n')
print(phone['udid'])
PY
)
cat release/recording-preservation/context.json
state=$(xcrun simctl list devices available --json | python3 -c 'import json,sys; print(next(d["state"] for rows in json.load(sys.stdin)["devices"].values() for d in rows if d["udid"]==sys.argv[1]))' "$device")
if [[ "$state" != Booted ]]; then xcrun simctl boot "$device"; fi
xcrun simctl bootstatus "$device" -b
test_exit=0
xcodebuild test -project ios/Athar.xcodeproj -scheme Athar -configuration Debug \
  -destination "platform=iOS Simulator,id=$device" \
  -derivedDataPath release/preservation-derived-data CODE_SIGNING_ALLOWED=NO \
  ENABLE_TESTABILITY=YES ONLY_ACTIVE_ARCH=YES -parallel-testing-enabled NO \
  'OTHER_SWIFT_FLAGS=$(inherited) -DNOOR_ACCEPTANCE_TESTING' \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 60 \
  -maximum-test-execution-time-allowance 90 \
  -only-testing:AtharTests/RecitationArchiveTests \
  -only-testing:AtharTests/LegacyRecordingFocusTests \
  -only-testing:AtharTests/MushafRecordingTests/testFailedRealDecodeReleasesOnlyOwnedAudioSessionWithoutDeletingBytes \
  -only-testing:AtharTests/MushafRecordingTests/testFailedDeactivationCanRetryWithoutReactivatingOrReplacingAudio \
  -only-testing:AtharTests/MushafRecordingTests/testFailedDeactivationCannotRetryAfterAnotherRecordingTakesOver \
  -resultBundlePath release/recording-preservation/actual-tests.xcresult || test_exit=$?
python3 - "$test_exit" <<'PY'
import json,sys
from pathlib import Path
p=Path('release/recording-preservation/context.json');data=json.loads(p.read_text())
data['testExit']=int(sys.argv[1]);p.write_text(json.dumps(data,indent=2)+'\n')
print('RECORDING_PRESERVATION_RESULT',json.dumps(data))
PY
exit "$test_exit"
