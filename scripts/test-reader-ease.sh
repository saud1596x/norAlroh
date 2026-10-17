#!/usr/bin/env bash
# Focused native regression; does NOT replace actual-ASR, microphone or release gates.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p release/reader-ease
xcodegen generate --spec ios/project.yml --project ios
device=$(python3 - <<'PY'
import json,subprocess
from pathlib import Path
runtime='com.apple.CoreSimulator.SimRuntime.iOS-26-2'
devices=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','--json']))
phones=[d for d in devices['devices'].get(runtime,[]) if d.get('isAvailable') and d['name']=='iPhone 17 Pro']
assert phones,'Exact iOS26.2/iPhone17Pro runtime is required'
Path('release/reader-ease/context.json').write_text(json.dumps({
 'sourceCommit':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),
 'xcode':subprocess.check_output(['xcodebuild','-version'],text=True).strip(),
 'runtime':runtime,'device':phones[0]['name'],'configuration':'Release',
 'scope':'Reader layout/touch areas, manual page lock, exact captured-word alignment replay, both journal write orders; NOT actual ASR rerun, device microphone, all-reciter timing or release acceptance'
},indent=2)+'\n')
print(phones[0]['udid'])
PY
)
cat release/reader-ease/context.json
state=$(xcrun simctl list devices available --json | python3 -c 'import json,sys;print(next(d["state"] for rows in json.load(sys.stdin)["devices"].values() for d in rows if d["udid"]==sys.argv[1]))' "$device")
if [[ "$state" != Booted ]]; then xcrun simctl boot "$device"; fi
xcrun simctl bootstatus "$device" -b
test_exit=0
xcodebuild test -project ios/Athar.xcodeproj -scheme Athar -configuration Release \
 -destination "platform=iOS Simulator,id=$device" \
 -derivedDataPath release/reader-ease-derived-data CODE_SIGNING_ALLOWED=NO \
 ENABLE_TESTABILITY=YES ONLY_ACTIVE_ARCH=YES -parallel-testing-enabled NO \
 'OTHER_SWIFT_FLAGS=$(inherited) -DNOOR_ACCEPTANCE_TESTING' \
 -test-timeouts-enabled YES -default-test-execution-time-allowance 60 \
 -maximum-test-execution-time-allowance 180 \
 -only-testing:AtharTests/NoorReaderCoreRegressionTests \
 -only-testing:AtharTests/QuranWordAlignmentTests \
 -only-testing:AtharTests/MushafViewportTests \
 -only-testing:AtharUITests/NoorContinuousReaderUITests \
 -resultBundlePath release/reader-ease/actual-tests.xcresult || test_exit=$?
python3 - "$test_exit" <<'PY'
import json,sys
from pathlib import Path
p=Path('release/reader-ease/context.json');d=json.loads(p.read_text());d['testExit']=int(sys.argv[1]);p.write_text(json.dumps(d,indent=2)+'\n')
print('READER_EASE_RESULT',json.dumps(d))
PY
exit "$test_exit"
