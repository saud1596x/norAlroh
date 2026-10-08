#!/usr/bin/env bash
set -euo pipefail
mkdir -p release/mushaf-balance
python3 scripts/select-xcode.py > release/mushaf-balance/xcode.env
source release/mushaf-balance/xcode.env
export DEVELOPER_DIR
python3 scripts/prepare-qcf-v2.py --output ios/Athar/Fonts
python3 scripts/prepare-mushaf-companion.py
cp release/qcf-v2-manifest.json ios/Athar/qcf-v2-manifest.json
xcodegen generate --spec ios/project.yml --project ios
python3 - <<'PY'
import json, subprocess
data = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'available', '--json']))
for _, devices in data['devices'].items():
    compact = next((d for d in devices if d.get('isAvailable') and d['name'].startswith('iPhone') and 'Pro' in d['name'] and 'Max' not in d['name']), None)
    large = next((d for d in devices if d.get('isAvailable') and d['name'].startswith('iPhone') and 'Pro Max' in d['name']), None)
    if compact and large:
        with open('release/mushaf-balance/devices.env', 'w') as f:
            f.write('NOOR_BALANCE_COMPACT=' + compact['udid'] + '\nNOOR_BALANCE_LARGE=' + large['udid'] + '\n')
        print('Actual phones:', compact['name'], '/', large['name'])
        break
else:
    raise SystemExit('Two iPhone display classes on one available runtime are required.')
PY
source release/mushaf-balance/devices.env
common=(-project ios/Athar.xcodeproj -scheme Athar -configuration Debug -derivedDataPath release/balance-derived-data CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES ONLY_ACTIVE_ARCH=YES)
xcrun simctl boot "$NOOR_BALANCE_COMPACT" || true
xcrun simctl bootstatus "$NOOR_BALANCE_COMPACT" -b
xcodebuild build-for-testing "${common[@]}" -destination "platform=iOS Simulator,id=$NOOR_BALANCE_COMPACT"
layout_exit=0
xcodebuild test-without-building "${common[@]}" -destination "platform=iOS Simulator,id=$NOOR_BALANCE_COMPACT" \
  -only-testing:AtharTests/InteractiveMushafTests -only-testing:AtharTests/MushafViewportTests \
  -only-testing:AtharTests/QCFV2ContentTests -parallel-testing-enabled NO \
  -only-testing:AtharTests/MushafRepetitionTests \
  -resultBundlePath release/mushaf-balance/all-604-pages.xcresult || layout_exit=$?
# Export failed native pages as well; diagnostic capture must never turn a
# failed layout gate green. A crash may leave only a partial result bundle.
if [[ ! -d release/mushaf-balance/all-604-pages.xcresult ]]; then
  [[ "$layout_exit" != 0 ]] || layout_exit=1
  exit "$layout_exit"
fi
xcrun xcresulttool export attachments --path release/mushaf-balance/all-604-pages.xcresult --output-path release/mushaf-balance/native-pages
python3 -m venv release/balance-python
release/balance-python/bin/pip install Pillow
# A playback failure must remain red, but must not suppress independent UI
# evidence on either screen size. Collect every gate, then return its failure.
noor_overall_exit="$layout_exit"
release/balance-python/bin/python scripts/export-mushaf-contact-sheets.py release/mushaf-balance/native-pages release/mushaf-balance/contact-sheets || noor_overall_exit=1
for noor_class in compact large; do
  if [[ "$noor_class" == compact ]]; then noor_device="$NOOR_BALANCE_COMPACT"; else noor_device="$NOOR_BALANCE_LARGE"; fi
  xcrun simctl boot "$noor_device" || true
  xcrun simctl bootstatus "$noor_device" -b
  xcrun simctl io "$noor_device" recordVideo --codec=h264 --force "release/mushaf-balance/reader-$noor_class.mp4" &
  noor_video_pid=$!
  stop_video() { kill -INT "$noor_video_pid" 2>/dev/null || true; wait "$noor_video_pid" || true; }
  trap stop_video EXIT
  noor_exit=0
  xcodebuild test-without-building "${common[@]}" -destination "platform=iOS Simulator,id=$noor_device" \
    -only-testing:AtharUITests/NoorInteractiveMushafUITests \
    -parallel-testing-enabled NO -resultBundlePath "release/mushaf-balance/reader-$noor_class.xcresult" || noor_exit=$?
  stop_video
  trap - EXIT
  if [[ -d "release/mushaf-balance/reader-$noor_class.xcresult" ]]; then
    xcrun xcresulttool export attachments --path "release/mushaf-balance/reader-$noor_class.xcresult" --output-path "release/mushaf-balance/reader-$noor_class-screens" || noor_overall_exit=1
  else
    noor_overall_exit=1
  fi
  [[ "$noor_exit" == 0 ]] || noor_overall_exit="$noor_exit"
done
exit "$noor_overall_exit"
