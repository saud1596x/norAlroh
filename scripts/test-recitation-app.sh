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
xcodebuild test -project ios/Athar.xcodeproj -scheme Athar -configuration Debug \
  -destination "platform=iOS Simulator,id=$noor_recitation_device" \
  -derivedDataPath release/recitation-app-derived-data CODE_SIGNING_ALLOWED=NO \
  ENABLE_TESTABILITY=YES ONLY_ACTIVE_ARCH=YES -parallel-testing-enabled NO \
  -only-testing:AtharTests/QuranRecognitionIntegrationTests \
  -resultBundlePath release/recitation-app/recognition-integration.xcresult
