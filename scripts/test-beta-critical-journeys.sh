#!/usr/bin/env bash
# Current integrated app journeys, not calibrated learner/full-release acceptance.
set -euo pipefail
cd "$(dirname "$0")/.."
remaining=${NOOR_BETA_REMAINING_CHECK:-0}
case "$remaining" in 0|1) ;; *) echo 'Unsupported beta journey scope'; exit 2;; esac
python3 scripts/check-native-test-selectors.py
python3 scripts/run-native-with-deadline.py --check 720
mkdir -p release/beta-journeys
xcodegen generate --spec ios/project-accounts.yml --project ios
device=$(python3 - <<'PY'
import json,os,subprocess
from pathlib import Path
runtime='com.apple.CoreSimulator.SimRuntime.iOS-26-2'
devices=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','--json']))
phone=next(d for d in devices['devices'][runtime] if d.get('isAvailable') and d['name']=='iPhone 17 Pro')
Path('release/beta-journeys/context.json').write_text(json.dumps({
 'sourceCommit':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),
 'xcode':subprocess.check_output(['xcodebuild','-version'],text=True).strip(),
 'runtime':runtime,'device':phone['name'],'configuration':'Release','projectSpec':'ios/project-accounts.yml',
 'scope':'Remaining whole-screen walkthrough, real twenty-page ward and actual simulator microphone start/background/resume only' if os.environ.get('NOOR_BETA_REMAINING_CHECK') == '1' else 'Integrated home/reader/adhkar/prayer/settings/legal navigation, twenty-page ward, reciter picker, notification logic and actual simulator microphone start. NOT physical learner accuracy, notification delivery, Apple sign-in E2E, all20wordtimings or entire Release suite',
 'remainingOnly': os.environ.get('NOOR_BETA_REMAINING_CHECK') == '1',
 'priorPartialRun': '6ad52c337550aed8108fef00' if os.environ.get('NOOR_BETA_REMAINING_CHECK') == '1' else None,
 'limits':'NOT fullRelease, physical learner accuracy, delivery, Apple sign-in E2E or all20wordtimings'
},indent=2)+'\n')
print(phone['udid'])
PY
)
state=$(xcrun simctl list devices available --json | python3 -c 'import json,sys;print(next(d["state"] for rows in json.load(sys.stdin)["devices"].values() for d in rows if d["udid"]==sys.argv[1]))' "$device")
if [[ "$state" != Booted ]]; then xcrun simctl boot "$device"; fi
xcrun simctl bootstatus "$device" -b
common=(-project ios/Athar.xcodeproj -scheme Athar -configuration Release
 -destination "platform=iOS Simulator,id=$device"
 -derivedDataPath release/continuous-reader-derived-data CODE_SIGNING_ALLOWED=NO
 ENABLE_TESTABILITY=YES ONLY_ACTIVE_ARCH=YES -parallel-testing-enabled NO
 'OTHER_SWIFT_FLAGS=$(inherited) -DNOOR_ACCEPTANCE_TESTING')
python3 scripts/run-native-with-deadline.py 720 xcodebuild build-for-testing "${common[@]}" \
 2>&1 | tee release/beta-journeys/build-log.txt
if [[ "$remaining" == 1 ]]; then
 # These four cases never completed in the preceding run. Retain that failed
 # result; do not rerun its63 passed units or its two passed UI cases. One
 # invocation avoids repeated package resolution/runner startup. All real
 # navigation/capture assertions remain, with a bounded combined deadline.
 xcrun simctl privacy "$device" grant microphone com.saud1596x.nooralruh
 remaining_exit=0
 python3 scripts/run-native-with-deadline.py 540 xcodebuild test-without-building "${common[@]}" \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 300 -maximum-test-execution-time-allowance 300 \
  -only-testing:AtharUITests/NoorAllScreensTests/testAllScreensWalkthrough \
  -only-testing:AtharUITests/NoorKhatmahUITests/testHomeContinuesOneTwentyPageWardAndKeepsStopInsideSameAction \
  -only-testing:AtharUITests/NoorMushafStudyUITests/testOneTapStartsActualInlineMicrophoneWithoutSetupOrAccount \
  -only-testing:AtharUITests/NoorMushafStudyUITests/testMicCaptureBackgroundResumeStaysInMushafWithoutHistory \
  -resultBundlePath release/beta-journeys/remaining.xcresult \
  2>&1 | tee release/beta-journeys/remaining-log.txt || remaining_exit=$?
 python3 scripts/export-reader-proof.py release/beta-journeys/remaining.xcresult
 python3 - "$remaining_exit" <<'PY'
import json,sys
from pathlib import Path
p=Path('release/beta-journeys/context.json');data=json.loads(p.read_text())
data['remainingExit']=int(sys.argv[1]);p.write_text(json.dumps(data,indent=2)+'\n')
print('NOOR_BETA_REMAINING_RESULT',json.dumps(data))
PY
 exit "$remaining_exit"
fi
navigation_exit=0
python3 scripts/run-native-with-deadline.py 600 xcodebuild test-without-building "${common[@]}" \
 -test-timeouts-enabled YES -default-test-execution-time-allowance 300 -maximum-test-execution-time-allowance 300 \
 -only-testing:AtharTests/AutomaticPrayerTests \
 -only-testing:AtharTests/PrayerNotificationPlanTests \
 -only-testing:AtharTests/NotificationReconciliationTests \
 -only-testing:AtharTests/NoorPersonalReminderTests \
 -only-testing:AtharTests/KhatmahJourneyTests \
 -only-testing:AtharTests/NoorAccountDeletionStateTests \
 -only-testing:AtharTests/NoorReciterTests \
 -only-testing:AtharTests/NoorReciterWordTimingTests \
 -only-testing:AtharUITests/NoorAllScreensTests/testAllScreensWalkthrough \
 -only-testing:AtharUITests/NoorKhatmahUITests/testHomeContinuesOneTwentyPageWardAndKeepsStopInsideSameAction \
 -only-testing:AtharUITests/NoorDailyEaseTests/testSeparateMorningAndEveningOpenReadableSessions \
 -only-testing:AtharUITests/NoorContinuousReaderUITests \
 -resultBundlePath release/beta-journeys/navigation.xcresult \
 2>&1 | tee release/beta-journeys/navigation-log.txt || navigation_exit=$?
# Grant the real simulator OS permission only for the separate actual capture
# journey. Never inject permission, PCM, fake completion or progress into app state.
xcrun simctl privacy "$device" grant microphone com.saud1596x.nooralruh
microphone_exit=0
python3 scripts/run-native-with-deadline.py 180 xcodebuild test-without-building "${common[@]}" \
 -test-timeouts-enabled YES -default-test-execution-time-allowance 60 -maximum-test-execution-time-allowance 90 \
 -only-testing:AtharUITests/NoorMushafStudyUITests/testOneTapStartsActualInlineMicrophoneWithoutSetupOrAccount \
 -only-testing:AtharUITests/NoorMushafStudyUITests/testMicCaptureBackgroundResumeStaysInMushafWithoutHistory \
 -resultBundlePath release/beta-journeys/microphone.xcresult \
 2>&1 | tee release/beta-journeys/microphone-log.txt || microphone_exit=$?
python3 scripts/export-reader-proof.py release/beta-journeys/navigation.xcresult
python3 scripts/export-reader-proof.py release/beta-journeys/microphone.xcresult
python3 - "$navigation_exit" "$microphone_exit" <<'PY'
import json,sys
from pathlib import Path
p=Path('release/beta-journeys/context.json');data=json.loads(p.read_text())
data['navigationExit']=int(sys.argv[1]);data['microphoneExit']=int(sys.argv[2])
p.write_text(json.dumps(data,indent=2)+'\n')
print('NOOR_BETA_JOURNEYS_RESULT',json.dumps(data))
PY
[[ "$navigation_exit" == 0 && "$microphone_exit" == 0 ]]
