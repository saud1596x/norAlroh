#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p release/khatmah-protection
python3 scripts/select-xcode.py > release/khatmah-protection/xcode.env
source release/khatmah-protection/xcode.env
export DEVELOPER_DIR
xcodegen generate --spec ios/project-focus.yml --project ios
xcodebuild -project ios/Athar.xcodeproj -scheme Athar -configuration Release -sdk iphoneos \
  -destination generic/platform=iOS -derivedDataPath release/khatmah-protection-focus-derived-data \
  CODE_SIGNING_ALLOWED=NO build
xcodegen generate --spec ios/project.yml --project ios
noor_protection_device=$(python3 - <<'PY'
import json, os, subprocess
large=os.environ.get('NOOR_DISPLAY_CLASS','compact')=='large'
devices=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','--json']))
phones=[d for runtime, rows in devices['devices'].items() if 'SimRuntime.iOS' in runtime for d in rows if d.get('isAvailable') and d['name'].startswith('iPhone') and ('Pro Max' in d['name'])==large]
assert phones, 'Requested iPhone size unavailable'
print(phones[0]['udid'])
PY
)
noor_protection_state=$(xcrun simctl list devices available --json | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(x["state"] for rows in d["devices"].values() for x in rows if x["udid"]==sys.argv[1]))' "$noor_protection_device")
if [[ "$noor_protection_state" != Booted ]]; then xcrun simctl boot "$noor_protection_device"; fi
xcrun simctl bootstatus "$noor_protection_device" -b
common=(-project ios/Athar.xcodeproj -scheme Athar -configuration Release
  -destination "platform=iOS Simulator,id=$noor_protection_device"
  -derivedDataPath release/khatmah-protection-derived-data CODE_SIGNING_ALLOWED=NO
  ENABLE_TESTABILITY=YES ONLY_ACTIVE_ARCH=YES -parallel-testing-enabled NO
  'OTHER_SWIFT_FLAGS=$(inherited) -DNOOR_ACCEPTANCE_TESTING')
xcodebuild build-for-testing "${common[@]}"
xcodebuild test-without-building "${common[@]}" \
  -only-testing:AtharTests/NoorKhatmahProtectionTests \
  -only-testing:AtharTests/NoorSalawatTests \
  -only-testing:AtharTests/WidgetTests \
  -only-testing:AtharTests/KhatmahJourneyTests \
  -resultBundlePath release/khatmah-protection/data.xcresult
xcrun simctl io "$noor_protection_device" recordVideo --codec=h264 --force release/khatmah-protection/actual-ui.mp4 &
noor_protection_video=$!
stop_video() { kill -INT "$noor_protection_video" 2>/dev/null || true; wait "$noor_protection_video" || true; }
trap stop_video EXIT
noor_protection_gate=0
xcodebuild test-without-building "${common[@]}" \
  -only-testing:AtharUITests/NoorLaunchTests \
  -only-testing:AtharUITests/NoorKhatmahProtectionUITests \
  -only-testing:AtharUITests/NoorSalawatUITests \
  -only-testing:AtharUITests/NoorKhatmahUITests \
  -resultBundlePath release/khatmah-protection/ui.xcresult || noor_protection_gate=$?
stop_video
trap - EXIT
if [[ -d release/khatmah-protection/ui.xcresult ]]; then
  xcrun xcresulttool export attachments --path release/khatmah-protection/ui.xcresult --output-path release/khatmah-protection/screens || noor_protection_gate=1
else
  noor_protection_gate=1
fi
exit "$noor_protection_gate"
