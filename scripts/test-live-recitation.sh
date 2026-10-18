#!/usr/bin/env bash
# Actual current-source Release tests, never a full-product/accuracy certificate.
set -euo pipefail
cd "$(dirname "$0")/.."
out=release/live-recitation
mkdir -p "$out"
python3 scripts/check-native-test-selectors.py
xcodebuild -version > "$out/xcode.txt"
git rev-parse HEAD > "$out/source.txt"
xcrun simctl list devices available --json > "$out/devices.json"
system_profiler SPAudioDataType -json > "$out/host-audio.json"
xcodegen generate --spec ios/project-accounts.yml --project ios
device=$(python3 - <<'PY'
import json
from pathlib import Path
data=json.loads(Path('release/live-recitation/devices.json').read_text())
phones=[(runtime,d) for runtime,rows in data['devices'].items() for d in rows
        if 'SimRuntime.iOS-26' in runtime and d.get('isAvailable') and d['name']=='iPhone 17 Pro']
assert phones, 'Actual supported iOS26/iPhone17Pro simulator required'
runtime,phone=max(phones,key=lambda item:item[0])
Path('release/live-recitation/context.json').write_text(json.dumps({
 'runtime':runtime,'device':phone['name'],'configuration':'Release','project':'project-accounts.yml',
 'limits':'NOT learner accuracy, physical microphone, all20reciter timing or fullRelease acceptance',
 'results':{}},indent=2)+'\n')
print(phone['udid'])
PY
)
xcrun simctl boot "$device" || true
xcrun simctl bootstatus "$device" -b
common=(-project ios/Athar.xcodeproj -scheme Athar -configuration Release
 -destination "platform=iOS Simulator,id=$device" -derivedDataPath release/live-recitation-derived
 CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES ONLY_ACTIVE_ARCH=YES -parallel-testing-enabled NO
 'OTHER_SWIFT_FLAGS=$(inherited) -DNOOR_ACCEPTANCE_TESTING')
python3 scripts/run-native-with-deadline.py 720 xcodebuild build-for-testing "${common[@]}" 2>&1 | tee "$out/build.txt"
failed=0
run_case() {
 local name=$1; shift
 local result=0
 python3 scripts/run-native-with-deadline.py 180 xcodebuild test-without-building "${common[@]}" \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 100 -maximum-test-execution-time-allowance 120 \
  "$@" -resultBundlePath "$out/$name.xcresult" 2>&1 | tee "$out/$name.txt" || result=$?
 python3 scripts/export-reader-proof.py "$out/$name.xcresult"
 if [[ -d "$out/screenshots" ]]; then mv "$out/screenshots" "$out/$name-screenshots"; fi
 python3 - "$name" "$result" <<'PY'
import json,sys
from pathlib import Path
p=Path('release/live-recitation/context.json');data=json.loads(p.read_text())
data['results'][sys.argv[1]]=int(sys.argv[2]);p.write_text(json.dumps(data,indent=2)+'\n')
print('NOOR_LIVE_RESULT',sys.argv[1],sys.argv[2])
PY
 [[ "$result" == 0 ]] || failed=1
}
run_case live-storage \
 -only-testing:AtharTests/QuranLiveRecitationStorageTests \
 -only-testing:AtharTests/QuranPracticeVisibilityTests \
 -only-testing:AtharTests/QuranMicrophoneInputLifecycleTests \
 -only-testing:AtharTests/QuranRecognitionIntegrationTests/testOpeningAndResumingCaptureDoesNotWaitForModelPreparation
xcrun simctl privacy "$device" grant microphone com.saud1596x.nooralruh
# Separate bundles preserve later results even when a CoreAudio test host dies.
run_case one-tap -only-testing:AtharUITests/NoorMushafStudyUITests/testOneTapStartsActualInlineMicrophoneWithoutSetupOrAccount
run_case background -only-testing:AtharUITests/NoorMushafStudyUITests/testMicCaptureBackgroundResumeStaysInMushafWithoutHistory
run_case privacy -only-testing:AtharUITests/NoorInteractiveMushafUITests/testExplicitRecitationRemovalAndMicrophoneSettings
python3 - <<'PY'
from pathlib import Path
import shutil
out=Path('release/live-recitation')
for file in Path.home().joinpath('Library/Logs/DiagnosticReports').glob('Athar*'):
 if file.is_file() and file.stat().st_size < 4_000_000: shutil.copyfile(file,out/file.name)
PY
exit "$failed"
