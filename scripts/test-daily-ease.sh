#!/usr/bin/env bash
# First-use notification, separated daily adhkar and audio cache regressions; not full release acceptance.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p release/daily-ease
xcodegen generate --spec ios/project.yml --project ios
device=$(python3 - <<'PY'
import json,subprocess
from pathlib import Path
runtime='com.apple.CoreSimulator.SimRuntime.iOS-26-2'
devices=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','--json']))
phones=[d for d in devices['devices'].get(runtime,[]) if d.get('isAvailable') and d['name']=='iPhone 17 Pro']
assert phones,'Exact iOS26.2/iPhone17Pro runtime is required'
phone=phones[0]
Path('release/daily-ease/context.json').write_text(json.dumps({
  'sourceCommit':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),
  'xcode':subprocess.check_output(['xcodebuild','-version'],text=True).strip(),
  'runtime':runtime,'device':phone['name'],'configuration':'Release',
  'scope':'Notifications consent and persisted choices, morning/evening content, reciter/cache integrity, native reading UI. Not full Release or device microphone acceptance'
},indent=2)+'\n')
print(phone['udid'])
PY
)
cat release/daily-ease/context.json
state=$(xcrun simctl list devices available --json | python3 -c 'import json,sys; print(next(d["state"] for rows in json.load(sys.stdin)["devices"].values() for d in rows if d["udid"]==sys.argv[1]))' "$device")
if [[ "$state" != Booted ]]; then xcrun simctl boot "$device"; fi
xcrun simctl bootstatus "$device" -b
test_exit=0
xcodebuild test -project ios/Athar.xcodeproj -scheme Athar -configuration Release \
  -destination "platform=iOS Simulator,id=$device" \
  -derivedDataPath release/daily-ease-derived-data CODE_SIGNING_ALLOWED=NO \
  ENABLE_TESTABILITY=YES ONLY_ACTIVE_ARCH=YES -parallel-testing-enabled NO \
  'OTHER_SWIFT_FLAGS=$(inherited) -DNOOR_ACCEPTANCE_TESTING' \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 60 \
  -maximum-test-execution-time-allowance 90 \
  -only-testing:AtharTests/KhatmahJourneyTests \
  -only-testing:AtharTests/MushafViewportTests \
  -only-testing:AtharTests/NotificationReconciliationTests \
  -only-testing:AtharTests/NoorPersonalReminderTests \
  -only-testing:AtharTests/AdhkarReadingTests \
  -only-testing:AtharTests/AdhkarCounterTests \
  -only-testing:AtharTests/NoorReciterTests \
  -only-testing:AtharTests/AudioDownloadTests/testReciterDownloadIdentityRejectsDifferentRecordingAndPartialTransfers \
  -only-testing:AtharUITests/NoorDailyEaseTests \
  -only-testing:AtharUITests/NoorKhatmahUITests/testHomeContinuesOneTwentyPageWardAndKeepsStopInsideSameAction \
  -resultBundlePath release/daily-ease/actual-tests.xcresult || test_exit=$?
python3 - "$test_exit" <<'PY'
import json,sys
from pathlib import Path
p=Path('release/daily-ease/context.json');data=json.loads(p.read_text())
data['testExit']=int(sys.argv[1]);p.write_text(json.dumps(data,indent=2)+'\n')
print('DAILY_EASE_RESULT',json.dumps(data))
PY
exit "$test_exit"
