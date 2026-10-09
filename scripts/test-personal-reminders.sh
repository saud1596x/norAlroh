#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p release/personal-reminders
python3 scripts/select-xcode.py > release/personal-reminders/xcode.env
source release/personal-reminders/xcode.env
export DEVELOPER_DIR
xcodegen generate --spec ios/project.yml --project ios
noor_reminder_device=$(python3 - <<'PY'
import json, os, subprocess
large=os.environ.get('NOOR_DISPLAY_CLASS','compact')=='large'
devices=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','--json']))
phones=[d for runtime, rows in devices['devices'].items() if 'SimRuntime.iOS' in runtime for d in rows if d.get('isAvailable') and d['name'].startswith('iPhone') and ('Pro Max' in d['name'])==large]
assert phones, 'Requested iPhone size unavailable'
print(phones[0]['udid'])
PY
)
noor_reminder_state=$(xcrun simctl list devices available --json | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(x["state"] for rows in d["devices"].values() for x in rows if x["udid"]==sys.argv[1]))' "$noor_reminder_device")
if [[ "$noor_reminder_state" != Booted ]]; then xcrun simctl boot "$noor_reminder_device"; fi
xcrun simctl bootstatus "$noor_reminder_device" -b
common=(-project ios/Athar.xcodeproj -scheme Athar -configuration Release
  -destination "platform=iOS Simulator,id=$noor_reminder_device"
  -derivedDataPath release/personal-reminders-derived-data CODE_SIGNING_ALLOWED=NO
  ENABLE_TESTABILITY=YES ONLY_ACTIVE_ARCH=YES -parallel-testing-enabled NO
  'OTHER_SWIFT_FLAGS=$(inherited) -DNOOR_ACCEPTANCE_TESTING')
xcodebuild build-for-testing "${common[@]}"
xcodebuild test-without-building "${common[@]}" \
  -only-testing:AtharTests/NoorPersonalReminderTests \
  -only-testing:AtharTests/NotificationReconciliationTests \
  -only-testing:AtharTests/PrayerNotificationPlanTests \
  -only-testing:AtharTests/MushafRepetitionTests \
  -only-testing:AtharTests/MushafMemorizationTests \
  -only-testing:AtharTests/WidgetTests \
  -resultBundlePath release/personal-reminders/data.xcresult
xcodebuild test-without-building "${common[@]}" \
  -only-testing:AtharUITests/NoorReminderUITests \
  -only-testing:AtharUITests/NoorLaunchTests \
  -only-testing:AtharUITests/NoorKhatmahProtectionUITests \
  -resultBundlePath release/personal-reminders/ui.xcresult
