#!/usr/bin/env bash
# Actual current-source Release tests, never a full-product/accuracy certificate.
set -euo pipefail
cd "$(dirname "$0")/.."
first_allow_only=${NOOR_MIC_FIRST_ALLOW_ONLY:-0}
case "$first_allow_only" in 0|1) ;; *) echo 'Invalid first-allow scope'; exit 2;; esac
out=release/live-recitation
mkdir -p "$out"
python3 scripts/check-native-test-selectors.py
xcodebuild -version > "$out/xcode.txt"
git rev-parse HEAD > "$out/source.txt"
xcrun simctl list devices available --json > "$out/devices.json"
system_profiler SPAudioDataType -json > "$out/host-audio.json"
xcodegen generate --spec ios/project-accounts.yml --project ios
device=$(python3 - <<'PY'
import json,os
from pathlib import Path
data=json.loads(Path('release/live-recitation/devices.json').read_text())
phones=[(runtime,d) for runtime,rows in data['devices'].items() for d in rows
        if 'SimRuntime.iOS-26' in runtime and d.get('isAvailable') and d['name']=='iPhone 17 Pro']
assert phones, 'Actual supported iOS26/iPhone17Pro simulator required'
runtime,phone=max(phones,key=lambda item:item[0])
Path('release/live-recitation/context.json').write_text(json.dumps({
 'runtime':runtime,'device':phone['name'],'configuration':'Release','project':'project-accounts.yml',
 'limits':'NOT learner accuracy, physical microphone, all20reciter timing or fullRelease acceptance',
 'firstMicrophoneAllowOnly':os.environ.get('NOOR_MIC_FIRST_ALLOW_ONLY') == '1',
 'results':{}},indent=2)+'\n')
print(phone['udid'])
PY
)
xcrun simctl boot "$device" || true
xcrun simctl bootstatus "$device" -b
derived=release/live-recitation-derived
if [[ "$first_allow_only" == 1 ]]; then derived=release/continuous-reader-derived-data; fi
common=(-project ios/Athar.xcodeproj -scheme Athar -configuration Release
 -destination "platform=iOS Simulator,id=$device" -derivedDataPath "$derived"
 CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES ONLY_ACTIVE_ARCH=YES -parallel-testing-enabled NO
 'OTHER_SWIFT_FLAGS=$(inherited) -DNOOR_ACCEPTANCE_TESTING')
# A cold full Release compile exceeded the former12-minute limit on GitHub
# before any test ran (39183130158). Keep test execution deadlines unchanged;
# give compilation its own bounded20-minute lane, never a passing timeout.
python3 scripts/run-native-with-deadline.py --build 1200 xcodebuild build-for-testing "${common[@]}" 2>&1 | tee "$out/build.txt"
failed=0
run_case() {
 local name=$1; shift
 local result=0
 local deadline=180
 local test_limits=(-test-timeouts-enabled YES -default-test-execution-time-allowance 100 -maximum-test-execution-time-allowance 120)
 # The unit invocation contains multiple cases and a cold XCTest/app installation.
 # On39185242274 its first case began ~175s after the last build timestamp,
 # leaving almost none of the former180s aggregate budget for execution.
 # Bound the whole suite separately; keep each case's100/120s XCTest limits
 # and every assertion unchanged. Single UI invocations retain180s.
 case "$name" in live-storage|startup-policy) deadline=600;;
  reader-geometry)
   deadline=600
   # This existing604-page case already declares180s. Live capture/UI cases
   # retain their original120s maximum and unchanged assertions.
   test_limits=(-test-timeouts-enabled YES -default-test-execution-time-allowance 100 -maximum-test-execution-time-allowance 180)
   ;;
 esac
 python3 scripts/run-native-with-deadline.py "$deadline" xcodebuild test-without-building "${common[@]}" \
  "${test_limits[@]}" \
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
if [[ "$first_allow_only" == 0 ]]; then
run_case live-storage \
 -only-testing:AtharTests/QuranLiveRecitationStorageTests \
 -only-testing:AtharTests/QuranLiveStoragePolicyTests \
 -only-testing:AtharTests/QuranListeningLocationTests \
 -only-testing:AtharTests/QuranPracticeVisibilityTests \
 -only-testing:AtharTests/QuranWordingAssessmentTests \
 -only-testing:AtharTests/QuranShortPassageTests \
 -only-testing:AtharTests/NoorContinuousMushafTests/testVisibleTextTracksRecognizedWordsAcrossAyahsWithoutHidingOrReshapingThePage \
 -only-testing:AtharTests/QuranMicrophoneInputLifecycleTests \
 -only-testing:AtharTests/NoorReaderCoreRegressionTests/testLiveWordLocationUsesExactNativePageWithoutVerseChangeAndRejectsMissingOrUnrelatedCursor \
 -only-testing:AtharTests/QuranRecognitionIntegrationTests/testOpeningAndResumingCaptureDoesNotWaitForModelPreparation \
 -only-testing:AtharTests/QuranRecognitionIntegrationTests/testActualRecognitionSessionPausesRestoresResumesAndFinishesWithoutReplacingAudio \
 -only-testing:AtharTests/QuranRecognitionIntegrationTests/testInterruptedActualReferenceProgressStaysVisibleThroughEmptyResumeUntilFreshRecognition \
 -only-testing:AtharTests/QuranRecognitionIntegrationTests/testDrainTimeoutWithActualPriorEvidenceExposesTextAndRejectsLateDecode \
 -only-testing:AtharTests/QuranRecognitionIntegrationTests/testHungLiveRecognitionKeepsAudioAndCannotRevealLateWords
xcrun simctl privacy "$device" grant microphone com.saud1596x.nooralruh
# Separate bundles preserve later results even when a CoreAudio test host dies.
run_case one-tap -only-testing:AtharUITests/NoorMushafStudyUITests/testOneTapStartsActualInlineMicrophoneWithoutSetupOrAccount
run_case background -only-testing:AtharUITests/NoorMushafStudyUITests/testMicCaptureBackgroundResumeStaysInMushafWithoutHistory
run_case privacy -only-testing:AtharUITests/NoorInteractiveMushafUITests/testExplicitRecitationRemovalAndMicrophoneSettings
# The user's reference video requires actual full-face/colored/hidden-text
# geometry and page-turn evidence. Reuse the existing unchanged assertions;
# these separate invocations survive an unrelated live recognition failure.
run_case reader-geometry \
 -only-testing:AtharTests/NoorReciterWordTimingTests \
 -only-testing:AtharTests/NoorContinuousMushafTests/testOnlyWordTimedRecordingsAreSelectableWithStableIdentityAndRestorableKeys \
 -only-testing:AtharTests/NoorContinuousMushafTests/testSelectingEveryReciterPreservesRecordingOwnershipAndDoesNotStartPlayback \
 -only-testing:AtharTests/NoorReaderCoreRegressionTests/testRemovedUntimedPreferencesStayHiddenAndTheirCacheIsNeverRelabelled \
 -only-testing:AtharTests/MushafViewportTests \
 -only-testing:AtharTests/NoorContinuousMushafTests/testOriginalTajweedLayersRenderAll604PagesAndPreserveHiddenWordGeometry
run_case reader-controls -only-testing:AtharUITests/NoorContinuousReaderUITests
run_case reader-library -only-testing:AtharUITests/NoorReciterLibraryTests
run_case reader-full-face -only-testing:AtharUITests/NoorReaderComfortUITests/testUserReferencePage14IsCenteredAndFullyVisible
run_case reader-entry -only-testing:AtharUITests/NoorReaderComfortUITests/testReaderOpensFullscreenAutomaticallyWithBalancedMicrophone
else
 # After changing the hardware-start boundary, verify cancellation/draining
 # and source display policy too. No injected audio counts as hardware proof.
 run_case startup-policy \
  -only-testing:AtharTests/QuranLiveRecitationStorageTests \
  -only-testing:AtharTests/QuranListeningLocationTests \
  -only-testing:AtharTests/QuranPracticeVisibilityTests \
  -only-testing:AtharTests/NoorReaderCoreRegressionTests/testLiveWordLocationUsesExactNativePageWithoutVerseChangeAndRejectsMissingOrUnrelatedCursor \
  -only-testing:AtharTests/QuranMicrophoneInputLifecycleTests
fi
# First approval is distinct from capture after an OS pre-grant. The app must
# start from the original tap; a second microphone tap cannot rescue the test.
xcrun simctl privacy "$device" reset microphone com.saud1596x.nooralruh
run_case first-allow -only-testing:AtharUITests/NoorMushafStudyUITests/testFirstMicrophoneAllowStartsCaptureFromTheOriginalTap
python3 - <<'PY'
from pathlib import Path
import shutil
out=Path('release/live-recitation')
for file in Path.home().joinpath('Library/Logs/DiagnosticReports').glob('Athar*'):
 if file.is_file() and file.stat().st_size < 4_000_000: shutil.copyfile(file,out/file.name)
PY
exit "$failed"
