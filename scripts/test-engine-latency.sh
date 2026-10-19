#!/usr/bin/env bash
# Diagnose the unchanged real-PCM latency assertion, not a release certificate.
set -euo pipefail
cd "$(dirname "$0")/.."
out=release/engine-latency
mkdir -p "$out"
git rev-parse HEAD > "$out/source.txt"
xcodebuild -version > "$out/xcode.txt"
xcodegen generate --spec ios/project-accounts.yml --project ios
device=$(python3 - <<'PY'
import json,subprocess
from pathlib import Path
runtime='com.apple.CoreSimulator.SimRuntime.iOS-26-2'
devices=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','--json']))
phones=[d for d in devices['devices'].get(runtime,[]) if d.get('isAvailable') and d['name']=='iPhone 17 Pro']
assert phones, 'Actual iOS26.2/iPhone17Pro required'
phone=phones[0]
Path('release/engine-latency/context.json').write_text(json.dumps({
 'source':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),
 'runtime':runtime,'device':phone['name'],'configuration':'Release',
 'scope':'Unchanged20second public-fixture cross-surah assertion with numeric model-stage timings. Not learner accuracy, physical microphone, fullRelease or release approval.'
},indent=2)+'\n',encoding='utf-8')
print(phone['udid'])
PY
)
xcrun simctl boot "$device" || true
xcrun simctl bootstatus "$device" -b
common=(-project ios/Athar.xcodeproj -scheme Athar -configuration Release
 -destination "platform=iOS Simulator,id=$device" -derivedDataPath release/engine-latency-derived
 CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES ONLY_ACTIVE_ARCH=YES -parallel-testing-enabled NO
 'OTHER_SWIFT_FLAGS=$(inherited) -DNOOR_ACCEPTANCE_TESTING')
python3 scripts/run-native-with-deadline.py --build 1200 xcodebuild build-for-testing "${common[@]}" 2>&1 | tee "$out/build.txt"
result=0
python3 scripts/run-native-with-deadline.py 600 xcodebuild test-without-building "${common[@]}" \
 -test-timeouts-enabled YES -default-test-execution-time-allowance 100 -maximum-test-execution-time-allowance 120 \
 -only-testing:AtharTests/NoorContinuousMushafTests/testRealPCMChangesSurahWithinOneListeningSessionWithoutStoppingForResults \
 -only-testing:AtharTests/PublishingContentTests \
 -resultBundlePath "$out/actual.xcresult" 2>&1 | tee "$out/tests.txt" || result=$?
python3 scripts/export-reader-proof.py "$out/actual.xcresult"
python3 - "$result" <<'PY'
import json,sys
from pathlib import Path
p=Path('release/engine-latency/context.json')
value=json.loads(p.read_text(encoding='utf-8'));value['testExit']=int(sys.argv[1])
p.write_text(json.dumps(value,indent=2)+'\n',encoding='utf-8')
PY
exit "$result"
