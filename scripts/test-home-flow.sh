#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/check-native-test-selectors.py
python3 -m unittest discover -s scripts/tests -p test_recording_ui_evidence.py -v
mkdir -p release/home-flow
python3 scripts/select-xcode.py > release/home-flow/xcode.env
source release/home-flow/xcode.env
export DEVELOPER_DIR
if [[ "${NOOR_RECITER_SMOKE_ONLY:-0}" != 1 ]]; then
xcodegen generate --spec ios/project-accounts.yml --project ios
xcodebuild -project ios/Athar.xcodeproj -scheme Athar -configuration Release -sdk iphoneos \
  -destination generic/platform=iOS -derivedDataPath release/home-flow-accounts-derived-data \
  CODE_SIGNING_ALLOWED=NO build
fi
xcodegen generate --spec ios/project.yml --project ios
noor_home_device=$(python3 - <<'PY'
import json, os, subprocess
large=os.environ.get('NOOR_DISPLAY_CLASS','compact')=='large'
devices=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','--json']))
phones=[d for runtime, rows in devices['devices'].items() if 'SimRuntime.iOS' in runtime for d in rows if d.get('isAvailable') and d['name'].startswith('iPhone') and ('Pro Max' in d['name'])==large]
assert phones, 'Requested iPhone size unavailable'
print(phones[0]['udid'])
PY
)
noor_home_state=$(xcrun simctl list devices available --json | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(x["state"] for rows in d["devices"].values() for x in rows if x["udid"]==sys.argv[1]))' "$noor_home_device")
if [[ "$noor_home_state" != Booted ]]; then xcrun simctl boot "$noor_home_device"; fi
xcrun simctl bootstatus "$noor_home_device" -b
common=(-project ios/Athar.xcodeproj -scheme Athar -configuration Release
  -destination "platform=iOS Simulator,id=$noor_home_device"
  -derivedDataPath release/home-flow-derived-data CODE_SIGNING_ALLOWED=NO
  ENABLE_TESTABILITY=YES ONLY_ACTIVE_ARCH=YES -parallel-testing-enabled NO
  'OTHER_SWIFT_FLAGS=$(inherited) -DNOOR_ACCEPTANCE_TESTING')
xcodebuild build-for-testing "${common[@]}"
if [[ "${NOOR_RECITER_SMOKE_ONLY:-0}" == 1 ]]; then
  xcodebuild test-without-building "${common[@]}" \
    -only-testing:AtharTests/NoorReciterTests \
    -only-testing:AtharTests/QuranGuidedPracticeTests \
    -only-testing:AtharUITests/NoorReciterLibraryTests \
    -only-testing:AtharUITests/NoorNavigationTests/testNativeHomeSaudiCitySelectionAndAdhkarSearch \
    -only-testing:AtharUITests/NoorAllScreensTests/testMushafHasNoSeparateMemorizationWorkspaceOrSessionHistory \
    -resultBundlePath release/home-flow/reciter-smoke.xcresult
  exit 0
fi
xcodebuild test-without-building "${common[@]}" \
  -only-testing:AtharUITests/NoorLaunchTests \
  -resultBundlePath release/home-flow/welcome.xcresult
xcodebuild test-without-building "${common[@]}" \
  -only-testing:AtharTests \
  -resultBundlePath release/home-flow/data.xcresult
python3 scripts/seed-recording-ui.py "$noor_home_device"
xcrun simctl privacy "$noor_home_device" reset microphone com.saud1596x.nooralruh
xcodebuild test-without-building "${common[@]}" \
  -only-testing:AtharUITests/NoorHomeFlowUITests \
  -only-testing:AtharUITests/NoorAllScreensTests \
  -only-testing:AtharUITests/NoorReciterLibraryTests \
  -only-testing:AtharUITests/NoorNavigationTests \
  -only-testing:AtharUITests/NoorPrayerDisplayUITests \
  -only-testing:AtharUITests/NoorRemovedFeaturesUITests \
  -only-testing:AtharUITests/NoorReaderComfortUITests \
  -only-testing:AtharUITests/NoorReminderUITests \
  -only-testing:AtharUITests/NoorKhatmahProtectionUITests \
  -only-testing:AtharUITests/NoorInteractiveMushafUITests/testMicrophoneDenialKeepsReaderAvailableAndStationary \
  -only-testing:AtharUITests/NoorInteractiveMushafUITests/testRecitationRemainsInsideReaderWithoutScopeOrHistoryScreens \
  -only-testing:AtharUITests/NoorInteractiveMushafUITests/testActualVersePlaybackFailureShowsNoticeAndRestoresReader \
  -only-testing:AtharUITests/NoorInteractiveMushafUITests/testExplicitRecitationRemovalAndMicrophoneSettings \
  -only-testing:AtharUITests/NoorInteractiveMushafUITests/testRenderingFailureWithHiddenToolsHasAccessibleRecovery \
  -resultBundlePath release/home-flow/ui.xcresult
python3 scripts/verify-recording-ui-removal.py "$noor_home_device"
# Verify the user-deletion action before intentionally creating fresh microphone
# recordings. Both display classes then exercise the actual permitted OS route.
xcrun simctl privacy "$noor_home_device" grant microphone com.saud1596x.nooralruh
xcodebuild test-without-building "${common[@]}" \
  -only-testing:AtharUITests/NoorMushafStudyUITests \
  -resultBundlePath release/home-flow/microphone-ui.xcresult
