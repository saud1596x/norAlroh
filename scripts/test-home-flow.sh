#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p release/home-flow
python3 scripts/select-xcode.py > release/home-flow/xcode.env
source release/home-flow/xcode.env
export DEVELOPER_DIR
xcodegen generate --spec ios/project-accounts.yml --project ios
xcodebuild -project ios/Athar.xcodeproj -scheme Athar -configuration Release -sdk iphoneos \
  -destination generic/platform=iOS -derivedDataPath release/home-flow-accounts-derived-data \
  CODE_SIGNING_ALLOWED=NO build
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
  -only-testing:AtharUITests/NoorRemovedFeaturesUITests \
  -only-testing:AtharUITests/NoorReaderComfortUITests \
  -only-testing:AtharUITests/NoorReminderUITests \
  -only-testing:AtharUITests/NoorKhatmahProtectionUITests \
  -only-testing:AtharUITests/NoorInteractiveMushafUITests/testMicrophoneDenialKeepsReaderAvailableAndStationary \
  -only-testing:AtharUITests/NoorInteractiveMushafUITests/testSecondaryScopeSelectsSurahAndRangeWithoutStartingMicrophone \
  -only-testing:AtharUITests/NoorInteractiveMushafUITests/testActualVersePlaybackFailureShowsNoticeAndRestoresReader \
  -only-testing:AtharUITests/NoorInteractiveMushafUITests/testPersistedReferenceRecordingTransportRemovalAndRelaunch \
  -resultBundlePath release/home-flow/ui.xcresult
