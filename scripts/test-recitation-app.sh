#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p release/recitation-app
noor_configuration="${NOOR_TEST_CONFIGURATION:-Debug}"
[[ "$noor_configuration" == Debug || "$noor_configuration" == Release ]] || { echo 'NOOR_TEST_CONFIGURATION must be Debug or Release.' >&2; exit 2; }
noor_display="${NOOR_DISPLAY_CLASS:-compact}"
[[ "$noor_display" == compact || "$noor_display" == large ]] || { echo 'NOOR_DISPLAY_CLASS must be compact or large.' >&2; exit 2; }
export NOOR_DISPLAY_CLASS="$noor_display"
python3 scripts/select-xcode.py > release/recitation-app/xcode.env
source release/recitation-app/xcode.env
export DEVELOPER_DIR
xcodegen generate --spec ios/project.yml --project ios
noor_recitation_device=$(python3 - <<'PY'
import json, os, subprocess
devices=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','--json']))
for group in devices['devices'].values():
    large=os.environ['NOOR_DISPLAY_CLASS']=='large'
    phone=next((x for x in group if x.get('isAvailable') and x['name'].startswith('iPhone') and ('Pro Max' in x['name'])==large), None)
    if phone:
        print(phone['udid'])
        break
else:
    raise SystemExit('Requested iPhone display class unavailable: '+os.environ['NOOR_DISPLAY_CLASS'])
PY
)
noor_device_state=$(xcrun simctl list devices available --json | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(x["state"] for rows in d["devices"].values() for x in rows if x["udid"]==sys.argv[1]))' "$noor_recitation_device")
if [[ "$noor_device_state" != Booted ]]; then xcrun simctl boot "$noor_recitation_device"; fi
xcrun simctl bootstatus "$noor_recitation_device" -b
python3 - "$noor_recitation_device" "$noor_configuration" <<'PYEVIDENCE'
import json, subprocess, sys
from pathlib import Path
udid, configuration=sys.argv[1:]
devices=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','--json']))
phone=next(x for rows in devices['devices'].values() for x in rows if x['udid']==udid)
Path('release/recitation-app/acceptance-context.json').write_text(json.dumps({
    'sourceCommit':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),
    'configuration':configuration,'simulator':phone['name'],'udid':udid,
    'acceptanceOnlyUnavailableAudioHook':True,
    'evidenceScope':'Simulator recognition, reference-recording transport, reader interaction and first-use guest continuation; not Apple authentication, physical-device voice or notification-sound acceptance'
},indent=2)+'\n')
PYEVIDENCE
common=(-project ios/Athar.xcodeproj -scheme Athar -configuration "$noor_configuration"
  -destination "platform=iOS Simulator,id=$noor_recitation_device"
  -derivedDataPath release/recitation-app-derived-data CODE_SIGNING_ALLOWED=NO
  ENABLE_TESTABILITY=YES ONLY_ACTIVE_ARCH=YES -parallel-testing-enabled NO
  'OTHER_SWIFT_FLAGS=$(inherited) -DNOOR_ACCEPTANCE_TESTING')
xcodebuild build-for-testing "${common[@]}"
noor_gate=0
# Run first-use navigation first so a broken entry screen cannot consume an
# entire recognition run before being detected. Record the real Simulator UI.
noor_video_pid=''
stop_video() {
  if [[ -n "$noor_video_pid" ]]; then
    kill -INT "$noor_video_pid" 2>/dev/null || true
    wait "$noor_video_pid" || true
    noor_video_pid=''
  fi
}
trap stop_video EXIT
xcrun simctl io "$noor_recitation_device" recordVideo --codec=h264 --force release/recitation-app/welcome-ui.mp4 &
noor_video_pid=$!
xcodebuild test-without-building "${common[@]}" \
  -only-testing:AtharUITests/NoorLaunchTests \
  -resultBundlePath release/recitation-app/welcome.xcresult || noor_gate=$?
stop_video
if [[ -d release/recitation-app/welcome.xcresult ]]; then
  xcrun xcresulttool export attachments --path release/recitation-app/welcome.xcresult --output-path release/recitation-app/welcome-screens || noor_gate=1
else
  noor_gate=1
fi
[[ "$noor_gate" == 0 ]] || exit "$noor_gate"
native_tests=(-only-testing:AtharTests/QuranRecognitionIntegrationTests -only-testing:AtharTests/MushafRecordingTests
  -only-testing:AtharTests/QuranRecognitionWorkerLifecycleTests -only-testing:AtharTests/NoorAccountDeletionStateTests
  -only-testing:AtharTests/PrayerLocationLifecycleTests -only-testing:AtharTests/NotificationReconciliationTests
  -only-testing:AtharTests/NoorPersonalReminderTests)
if [[ "${NOOR_ALL_NATIVE_TESTS:-0}" == 1 ]]; then native_tests=(-only-testing:AtharTests); fi
xcodebuild test-without-building "${common[@]}" \
  "${native_tests[@]}" \
  -resultBundlePath release/recitation-app/recognition-integration.xcresult || noor_gate=$?
python3 scripts/seed-recording-ui.py "$noor_recitation_device"
# Actual reader/permission UI and reference-audio transport, not live recitation.
xcrun simctl privacy "$noor_recitation_device" reset microphone com.saud1596x.nooralruh || true
xcrun simctl io "$noor_recitation_device" recordVideo --codec=h264 --force release/recitation-app/reader-and-recording-ui.mp4 &
noor_video_pid=$!
xcodebuild test-without-building "${common[@]}" \
  -only-testing:AtharUITests/NoorInteractiveMushafUITests/testMicrophoneDenialKeepsReaderAvailableAndStationary \
  -only-testing:AtharUITests/NoorInteractiveMushafUITests/testSecondaryScopeSelectsSurahAndRangeWithoutStartingMicrophone \
  -only-testing:AtharUITests/NoorInteractiveMushafUITests/testActualVersePlaybackFailureShowsNoticeAndRestoresReader \
  -only-testing:AtharUITests/NoorInteractiveMushafUITests/testExplicitRecitationRemovalAndMicrophoneSettings \
  -only-testing:AtharUITests/NoorInteractiveMushafUITests/testRenderingFailureWithHiddenToolsHasAccessibleRecovery \
  -resultBundlePath release/recitation-app/microphone-denial.xcresult || noor_gate=$?
python3 scripts/verify-recording-ui-removal.py "$noor_recitation_device" || noor_gate=1
stop_video
trap - EXIT
if [[ -d release/recitation-app/microphone-denial.xcresult ]]; then
  xcrun xcresulttool export attachments --path release/recitation-app/microphone-denial.xcresult --output-path release/recitation-app/microphone-denial-screens || noor_gate=1
else
  noor_gate=1
fi
exit "$noor_gate"
