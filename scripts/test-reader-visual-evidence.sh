#!/usr/bin/env bash
# UI-only complement to the completed 604-page geometry and 47-unit checks.
# Does not claim a new full Release, hardware audio, or acoustic acceptance.
set -euo pipefail
cd "$(dirname "$0")/.."
# Validate against the shared runner before downloading or generating anything.
python3 scripts/run-native-with-deadline.py --check 720
mkdir -p release/reader-visual
xcodegen generate --spec ios/project-accounts.yml --project ios
device=$(python3 - <<'PY'
import json, subprocess
from pathlib import Path
runtime = 'com.apple.CoreSimulator.SimRuntime.iOS-26-2'
devices = json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','--json']))
phones = [d for d in devices['devices'].get(runtime, []) if d.get('isAvailable') and d['name'] == 'iPhone 17 Pro']
assert phones, 'Exact iOS26.2/iPhone17Pro runtime is required'
Path('release/reader-visual/context.json').write_text(json.dumps({
 'sourceCommit': subprocess.check_output(['git','rev-parse','HEAD'], text=True).strip(),
 'xcode': subprocess.check_output(['xcodebuild','-version'], text=True).strip(),
 'runtime': runtime, 'device': phones[0]['name'], 'configuration': 'Release',
 'scope': 'UI ONLY: current normal/Tajweed page604, actual yellow selection, controls, full-screen space, reference page14 original screenshots. Complements prior47unit/all604geometry pass; NOT fullRelease, hardware microphone/speaker, all-reader timing or accuracy acceptance'
}, indent=2) + '\n')
print(phones[0]['udid'])
PY
)
cat release/reader-visual/context.json
state=$(xcrun simctl list devices available --json | python3 -c 'import json,sys;print(next(d["state"] for rows in json.load(sys.stdin)["devices"].values() for d in rows if d["udid"]==sys.argv[1]))' "$device")
if [[ "$state" != Booted ]]; then xcrun simctl boot "$device"; fi
xcrun simctl bootstatus "$device" -b
test_exit=0
python3 scripts/run-native-with-deadline.py 720 xcodebuild test \
 -project ios/Athar.xcodeproj -scheme Athar -configuration Release \
 -destination "platform=iOS Simulator,id=$device" \
 -derivedDataPath release/continuous-reader-derived-data CODE_SIGNING_ALLOWED=NO \
 ENABLE_TESTABILITY=YES ONLY_ACTIVE_ARCH=YES -parallel-testing-enabled NO \
 'OTHER_SWIFT_FLAGS=$(inherited) -DNOOR_ACCEPTANCE_TESTING' \
 -test-timeouts-enabled YES -default-test-execution-time-allowance 60 \
 -maximum-test-execution-time-allowance 180 \
 -only-testing:AtharUITests/NoorContinuousReaderUITests \
 -only-testing:AtharUITests/NoorReaderComfortUITests/testReaderOpensFullscreenAutomaticallyWithBalancedMicrophone \
 -only-testing:AtharUITests/NoorReaderComfortUITests/testUserReferencePage14IsCenteredAndFullyVisible \
 -resultBundlePath release/reader-visual/actual-tests.xcresult \
 2>&1 | tee release/reader-visual/native-test-log.txt || test_exit=$?
# Export original attachments even if a selected UI assertion failed.
python3 scripts/export-reader-proof.py release/reader-visual/actual-tests.xcresult
python3 - "$test_exit" <<'PY'
import json,sys
from pathlib import Path
p=Path('release/reader-visual/context.json');d=json.loads(p.read_text())
d['testExit']=int(sys.argv[1]);p.write_text(json.dumps(d,indent=2)+'\n')
print('READER_VISUAL_RESULT',json.dumps(d))
PY
exit "$test_exit"
