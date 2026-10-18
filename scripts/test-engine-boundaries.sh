#!/usr/bin/env bash
# Focused acoustic-boundary/native ASR verification. Not speaker/mic/release acceptance.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/check-native-test-selectors.py
repair=${NOOR_READER_REPAIR_CHECK:-0}
case "$repair" in 0|1) ;; *) echo 'Unsupported reader repair scope'; exit 2;; esac
python3 scripts/run-native-with-deadline.py --check "${NOOR_NATIVE_TEST_DEADLINE:-600}"
mkdir -p release/engine-boundaries
system_profiler SPAudioDataType -json > release/engine-boundaries/host-audio.json
xcodegen generate --spec ios/project-accounts.yml --project ios
device=$(python3 - <<'PY'
import json,os,subprocess
from pathlib import Path
runtime='com.apple.CoreSimulator.SimRuntime.iOS-26-2'
rows=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','--json']))
phone=next(d for d in rows['devices'][runtime] if d['name']=='iPhone 17 Pro' and d.get('isAvailable'))
Path('release/engine-boundaries/context.json').write_text(json.dumps({
 'sourceCommit':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),
 'xcode':subprocess.check_output(['xcodebuild','-version'],text=True).strip(),
 'runtime':runtime,'device':phone['name'],'configuration':'Release','projectSpec':'ios/project-accounts.yml',
 'scope':'Remote rejected-word boundaries/source preservation + genuine bundled public PCM cross-surah ASR. NOT remote iPhone/server E2E, speaker playback, microphone hardware, all-reader timings or full release',
 'readerRepairCheck': os.environ.get('NOOR_READER_REPAIR_CHECK') == '1'
},indent=2)+'\n')
print(phone['udid'])
PY
)
state=$(xcrun simctl list devices available --json | python3 -c 'import json,sys;print(next(d["state"] for rows in json.load(sys.stdin)["devices"].values() for d in rows if d["udid"]==sys.argv[1]))' "$device")
if [[ "$state" != Booted ]]; then xcrun simctl boot "$device"; fi
xcrun simctl bootstatus "$device" -b
additional_tests=()
if [[ "$repair" == 1 ]]; then
 xcrun simctl privacy "$device" reset microphone
 additional_tests=(
  -only-testing:AtharTests/NoorMicrophoneCueTests
  -only-testing:AtharTests/MushafViewportTests
  -only-testing:AtharTests/QCFV2ContentTests/testFirstAndRepeatedOpenUseVerifiedPackagedEditionWithoutNetworkOrCacheWrite
  -only-testing:AtharUITests/NoorInteractiveMushafUITests/testMicrophoneDenialKeepsReaderAvailableAndStationary
  -only-testing:AtharUITests/NoorReaderComfortUITests/testRepeatedPageTurnsStayInTheReadyReaderWithoutDownloadUI
  -only-testing:AtharUITests/NoorReaderComfortUITests/testReaderOpensFullscreenAutomaticallyWithBalancedMicrophone
 )
fi
result=0
python3 scripts/run-native-with-deadline.py "${NOOR_NATIVE_TEST_DEADLINE:-600}" xcodebuild test \
 -project ios/Athar.xcodeproj -scheme Athar -configuration Release \
 -destination "platform=iOS Simulator,id=$device" -derivedDataPath release/continuous-reader-derived-data \
 CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES ONLY_ACTIVE_ARCH=YES -parallel-testing-enabled NO \
 'OTHER_SWIFT_FLAGS=$(inherited) -DNOOR_ACCEPTANCE_TESTING' \
 -test-timeouts-enabled YES -default-test-execution-time-allowance 60 -maximum-test-execution-time-allowance 180 \
 -only-testing:AtharTests/QuranRemoteProtocolTests \
 -only-testing:AtharTests/QuranWordAlignmentTests \
 -only-testing:AtharTests/QuranRecognitionWorkerLifecycleTests \
 -only-testing:AtharTests/QuranRecognitionAudioTests \
 -only-testing:AtharTests/QuranMicrophoneInputLifecycleTests \
 -only-testing:AtharTests/QuranPracticeVisibilityTests \
 -only-testing:AtharTests/QuranListeningLocationTests \
 -only-testing:AtharTests/QuranLiveRecitationStorageTests \
 -only-testing:AtharTests/QuranLiveStoragePolicyTests \
 -only-testing:AtharTests/QuranIndependentAgreementTests \
 -only-testing:AtharTests/NoorReaderCoreRegressionTests/testVisibilityAndAnalysisPreserveEvidenceInBothDiskWriteOrders \
 -only-testing:AtharTests/QuranObservedSpeechTests/testInputGuidanceUsesPCMAndDoesNotTreatSilenceOrBriefPeaksAsMistakes \
 -only-testing:AtharTests/QuranObservedSpeechTests/testSignalFaultsCountActualCaptureFramesAndGuidanceRecoversAfterSustainedHealthyAudio \
 -only-testing:AtharTests/QuranObservedSpeechTests/testNoSpeechWindowKeepsStrictIdentityEvenWhenItsObservationArrayIsEmpty \
 -only-testing:AtharTests/NoorContinuousMushafTests/testRealPCMChangesSurahWithinOneListeningSessionWithoutStoppingForResults \
 -only-testing:AtharTests/QuranRecognitionIntegrationTests/testOpeningAndResumingCaptureDoesNotWaitForModelPreparation \
 -only-testing:AtharTests/QuranRecognitionIntegrationTests/testActualInitialPrefixCannotCompleteAnIsolatedScopeFromDecoderConfidenceAlone \
 -only-testing:AtharTests/QuranRecognitionIntegrationTests/testQuietActualReferenceStillAnchorsWhileNoiseCannotRevealWords \
 -only-testing:AtharTests/QuranRecognitionIntegrationTests/testVeryWeakActualSpeechAnchorsButAmplifiedWeakNoiseDoesNot \
 -only-testing:AtharTests/QuranRecognitionIntegrationTests/testActualQuietReferenceWithDCFaultStillAnchorsAndFlatlineCannotRevealWords \
 -only-testing:AtharTests/QuranRecognitionIntegrationTests/testActualBackendOnReferenceAndEditedOmissionKeepsAssessmentProvisional \
 "${additional_tests[@]}" \
 -resultBundlePath release/engine-boundaries/actual-tests.xcresult 2>&1 | tee release/engine-boundaries/native-test-log.txt || result=$?
if [[ "$result" != 0 ]]; then
 # Preserve the actual app/XCTest boundary on a startup timeout. A missing
 # test-case line is not proof that an app test, recognizer or device failed.
 python3 scripts/run-native-with-deadline.py 15 xcrun simctl spawn "$device" log show \
  --last 5m --style compact --predicate 'process == "Athar" OR subsystem BEGINSWITH "com.apple.dt.xctest"' \
  > release/engine-boundaries/failed-test-startup.txt 2>&1 || true
fi
if [[ "$repair" == 1 ]]; then python3 scripts/export-reader-proof.py release/engine-boundaries/actual-tests.xcresult; fi
python3 - "$result" <<'PY'
import json,sys
from pathlib import Path
p=Path('release/engine-boundaries/context.json');d=json.loads(p.read_text());d['testExit']=int(sys.argv[1]);p.write_text(json.dumps(d,indent=2)+'\n');print('NOOR_ENGINE_BOUNDARIES_RESULT',json.dumps(d))
PY
exit "$result"
