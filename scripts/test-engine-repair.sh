#!/usr/bin/env bash
# Focused repair verification. Never replaces all604/UI/full release gates.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p release/engine-repair
xcodegen generate --spec ios/project-accounts.yml --project ios
device=$(python3 - <<'PY'
import json,subprocess
from pathlib import Path
runtime='com.apple.CoreSimulator.SimRuntime.iOS-26-2'
rows=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','--json']))
phone=next(d for d in rows['devices'][runtime] if d['name']=='iPhone 17 Pro' and d.get('isAvailable'))
Path('release/engine-repair/context.json').write_text(json.dumps({
 'sourceCommit':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),
 'xcode':subprocess.check_output(['xcodebuild','-version'],text=True).strip(),
 'runtime':runtime,'device':phone['name'],'configuration':'Release','projectSpec':'ios/project-accounts.yml',
 'scope':'Focused ambiguity/real public PCM session/remote contracts; NOT all604, UI, physical microphone or full release'
},indent=2)+'\n')
print(phone['udid'])
PY
)
if ! xcrun simctl list devices available --json | python3 -c 'import json,sys; assert next(d for rows in json.load(sys.stdin)["devices"].values() for d in rows if d["udid"]==sys.argv[1])["state"]=="Booted"' "$device"; then
  xcrun simctl boot "$device"
fi
xcrun simctl bootstatus "$device" -b
common=(-project ios/Athar.xcodeproj -scheme Athar -configuration Release
 -destination "platform=iOS Simulator,id=$device" -derivedDataPath release/continuous-reader-derived-data
 CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES ONLY_ACTIVE_ARCH=YES -parallel-testing-enabled NO
 'OTHER_SWIFT_FLAGS=$(inherited) -DNOOR_ACCEPTANCE_TESTING')
xcodebuild build-for-testing "${common[@]}"
python3 scripts/sample-test-audio-hang.py "$device" release/engine-repair/stacks &
sampler=$!
result=0
xcodebuild test-without-building "${common[@]}" \
 -test-timeouts-enabled YES -default-test-execution-time-allowance 60 -maximum-test-execution-time-allowance 180 \
 -only-testing:AtharTests/NoorContinuousMushafTests/testRollingWindowTracksIndependentPassagesInAudioOrderWithoutFillingTheGap \
 -only-testing:AtharTests/NoorReaderCoreRegressionTests \
 -only-testing:AtharTests/NoorReciterWordTimingTests \
 -only-testing:AtharTests/QuranRemoteProtocolTests \
 -only-testing:AtharTests/QuranWordAlignmentTests \
 -only-testing:AtharTests/QuranRecognitionIntegrationTests/testActualRecognitionSessionPausesRestoresResumesAndFinishesWithoutReplacingAudio \
 -only-testing:AtharTests/QuranRecognitionIntegrationTests/testOpeningAndResumingCaptureDoesNotWaitForModelPreparation \
 -resultBundlePath release/engine-repair/actual-tests.xcresult 2>&1 | tee release/engine-repair/native-test-log.txt || result=$?
kill "$sampler" 2>/dev/null || true
wait "$sampler" 2>/dev/null || true
python3 - "$result" <<'PY'
import json,sys
from pathlib import Path
p=Path('release/engine-repair/context.json');d=json.loads(p.read_text());d['testExit']=int(sys.argv[1]);p.write_text(json.dumps(d,indent=2)+'\n');print('NOOR_ENGINE_REPAIR_RESULT',json.dumps(d))
for p in sorted(Path('release/engine-repair/stacks').glob('*.txt')): print('ACTUAL_SESSION_STACK',p.name,p.read_text(errors='replace')[:24000])
PY
exit "$result"
