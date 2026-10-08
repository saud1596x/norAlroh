#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p release/recitation-app
python3 scripts/select-xcode.py > release/recitation-app/xcode.env
source release/recitation-app/xcode.env
export DEVELOPER_DIR
xcodegen generate --spec ios/project.yml --project ios
noor_recitation_device=$(python3 - <<'PY'
import json, subprocess
devices=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','--json']))
for group in devices['devices'].values():
    phone=next((x for x in group if x.get('isAvailable') and x['name'].startswith('iPhone')), None)
    if phone:
        print(phone['udid'])
        break
else:
    raise SystemExit('No available iPhone simulator')
PY
)
xcrun simctl boot "$noor_recitation_device" || true
xcrun simctl bootstatus "$noor_recitation_device" -b
common=(-project ios/Athar.xcodeproj -scheme Athar -configuration Debug
  -destination "platform=iOS Simulator,id=$noor_recitation_device"
  -derivedDataPath release/recitation-app-derived-data CODE_SIGNING_ALLOWED=NO
  ENABLE_TESTABILITY=YES ONLY_ACTIVE_ARCH=YES -parallel-testing-enabled NO)
xcodebuild build-for-testing "${common[@]}"
noor_gate=0
xcodebuild test-without-building "${common[@]}" \
  -only-testing:AtharTests/QuranRecognitionIntegrationTests \
  -resultBundlePath release/recitation-app/recognition-integration.xcresult || noor_gate=$?
# This is real permission-denial UI evidence, not a live recitation claim.
xcrun simctl privacy "$noor_recitation_device" reset microphone com.saud1596x.nooralruh || true
xcrun simctl io "$noor_recitation_device" recordVideo --codec=h264 --force release/recitation-app/microphone-denial.mp4 &
noor_video_pid=$!
stop_video() { kill -INT "$noor_video_pid" 2>/dev/null || true; wait "$noor_video_pid" || true; }
trap stop_video EXIT
xcodebuild test-without-building "${common[@]}" \
  -only-testing:AtharUITests/NoorInteractiveMushafUITests/testMicrophoneDenialKeepsReaderAvailableAndStationary \
  -resultBundlePath release/recitation-app/microphone-denial.xcresult || noor_gate=$?
stop_video
trap - EXIT
if [[ -d release/recitation-app/microphone-denial.xcresult ]]; then
  xcrun xcresulttool export attachments --path release/recitation-app/microphone-denial.xcresult --output-path release/recitation-app/microphone-denial-screens || noor_gate=1
else
  noor_gate=1
fi
exit "$noor_gate"
