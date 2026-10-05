#!/usr/bin/env bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'اختبارات iOS تحتاج macOS وXcode؛ شغّل ios-quality في Codemagic من جهاز PC.' >&2
  exit 2
fi
command -v xcodegen >/dev/null || { echo 'ثبّت XcodeGen أولًا: brew install xcodegen' >&2; exit 2; }
XCODE_VERSION_MAJOR="$(xcodebuild -version | sed -n '1s/Xcode \([0-9]*\).*/\1/p')"
[[ "$XCODE_VERSION_MAJOR" -ge 26 ]] || { echo 'استخدم Xcode 26 أو أحدث.' >&2; exit 2; }
INFO_HASH_BEFORE="$(shasum -a 256 "$PROJECT_ROOT/ios/Athar/Info.plist" | cut -d ' ' -f 1)"
xcodegen generate --spec "$PROJECT_ROOT/ios/project.yml" --project "$PROJECT_ROOT/ios"
INFO_HASH_AFTER="$(shasum -a 256 "$PROJECT_ROOT/ios/Athar/Info.plist" | cut -d ' ' -f 1)"
[[ "$INFO_HASH_BEFORE" == "$INFO_HASH_AFTER" ]] || { echo 'Project generation modified Info.plist; restore the intended app metadata before continuing.' >&2; exit 2; }
SIMULATOR_ID="$(xcrun simctl list devices available --json | python3 -c 'import json,sys; d=json.load(sys.stdin); candidates=[x["udid"] for k,v in d["devices"].items() if "SimRuntime.iOS" in k for x in v if x.get("isAvailable") and x["name"].startswith("iPhone")]; print(candidates[0] if candidates else "")')"
[[ -n "$SIMULATOR_ID" ]] || { echo 'نزّل محاكي iPhone من إعدادات Xcode.' >&2; exit 2; }
TEST_CONFIGURATION="${NOOR_TEST_CONFIGURATION:-Debug}"
[[ "$TEST_CONFIGURATION" == Debug || "$TEST_CONFIGURATION" == Release ]] || { echo 'NOOR_TEST_CONFIGURATION must be Debug or Release.' >&2; exit 2; }
[[ ! -e "$PROJECT_ROOT/release/native-unit.xcresult" && ! -e "$PROJECT_ROOT/release/native-ui.xcresult" ]] || { echo 'احتفظ بنتائج التشغيل السابق ثم انقلها قبل إعادة الاختبار.' >&2; exit 2; }
xcodebuild build -project "$PROJECT_ROOT/ios/Athar.xcodeproj" -scheme Athar -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
xcodebuild test -project "$PROJECT_ROOT/ios/Athar.xcodeproj" -scheme Athar -configuration "$TEST_CONFIGURATION" -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -only-testing:AtharTests -parallel-testing-enabled NO -resultBundlePath "$PROJECT_ROOT/release/native-unit.xcresult" CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES
CAPTURE_PID=''
finish_capture() {
  if [[ -n "$CAPTURE_PID" ]]; then kill -INT "$CAPTURE_PID" 2>/dev/null || true; wait "$CAPTURE_PID" || true; CAPTURE_PID=''; fi
}
trap finish_capture EXIT
if [[ "${NOOR_RECORD_VIDEO:-0}" == 1 ]]; then
  xcrun simctl bootstatus "$SIMULATOR_ID" -b
  xcrun simctl io "$SIMULATOR_ID" recordVideo --codec=h264 --force "$PROJECT_ROOT/release/native-navigation.mp4" &
  CAPTURE_PID=$!
fi
UI_EXIT=0
xcodebuild test -project "$PROJECT_ROOT/ios/Athar.xcodeproj" -scheme Athar -configuration "$TEST_CONFIGURATION" -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -only-testing:AtharUITests -parallel-testing-enabled NO -resultBundlePath "$PROJECT_ROOT/release/native-ui.xcresult" CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES || UI_EXIT=$?
finish_capture
GALLERY_EXIT=0
python3 "$PROJECT_ROOT/scripts/export-native-gallery.py" || GALLERY_EXIT=$?
[[ "$UI_EXIT" == 0 && "$GALLERY_EXIT" == 0 ]] || { echo 'Native UI tests or complete screen capture failed; inspect actual artifacts.' >&2; exit 1; }
python3 "$PROJECT_ROOT/scripts/native-build-report.py"
