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
SIMULATOR_FAMILY="${NOOR_SIMULATOR_FAMILY:-iPhone}"
[[ "$SIMULATOR_FAMILY" == iPhone || "$SIMULATOR_FAMILY" == iPad ]] || { echo "NOOR_SIMULATOR_FAMILY must be iPhone or iPad." >&2; exit 2; }
export NOOR_SIMULATOR_FAMILY="$SIMULATOR_FAMILY"
# Capture on the large display classes required by App Store Connect.
SIMULATOR_ID="$(xcrun simctl list devices available --json | python3 -c '
import json,sys,os
family=os.environ["NOOR_SIMULATOR_FAMILY"]
devices=[x for runtime,items in json.load(sys.stdin)["devices"].items() if "SimRuntime.iOS" in runtime for x in items if x.get("isAvailable")]
if family == "iPhone":
    candidates=[x for x in devices if x["name"].startswith("iPhone") and "Pro Max" in x["name"]]
else:
    candidates=[x for x in devices if x["name"].startswith("iPad") and ("13-inch" in x["name"] or "12.9-inch" in x["name"])]
print(candidates[0]["udid"] if candidates else "")
')"
[[ -n "$SIMULATOR_ID" ]] || { echo "Install an iPhone Pro Max or 13-inch iPad simulator for App Store screenshot capture ($SIMULATOR_FAMILY)." >&2; exit 2; }
TEST_CONFIGURATION="${NOOR_TEST_CONFIGURATION:-Debug}"
[[ "$TEST_CONFIGURATION" == Debug || "$TEST_CONFIGURATION" == Release ]] || { echo 'NOOR_TEST_CONFIGURATION must be Debug or Release.' >&2; exit 2; }
[[ ! -e "$PROJECT_ROOT/release/native-unit.xcresult" && ! -e "$PROJECT_ROOT/release/native-ui.xcresult" ]] || { echo 'احتفظ بنتائج التشغيل السابق ثم انقلها قبل إعادة الاختبار.' >&2; exit 2; }
xcodebuild build -project "$PROJECT_ROOT/ios/Athar.xcodeproj" -scheme Athar -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
UNIT_EXIT=0
# Keep first-use reset and genuine unavailable-audio fixtures exclusive to test
# builds. The unsigned device build above and signed publishing retain their
# production flags and never receive these launch-argument hooks.
ACCEPTANCE_FLAGS='OTHER_SWIFT_FLAGS=$(inherited) -DNOOR_ACCEPTANCE_TESTING'
xcodebuild test -project "$PROJECT_ROOT/ios/Athar.xcodeproj" -scheme Athar -configuration "$TEST_CONFIGURATION" -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -only-testing:AtharTests -parallel-testing-enabled NO -resultBundlePath "$PROJECT_ROOT/release/native-unit.xcresult" CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES "$ACCEPTANCE_FLAGS" || UNIT_EXIT=$?
# Collect actual UI evidence even when an independent unit/integration test
# fails. The combined check still fails; a network outage is never a pass.
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
xcodebuild test -project "$PROJECT_ROOT/ios/Athar.xcodeproj" -scheme Athar -configuration "$TEST_CONFIGURATION" -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -only-testing:AtharUITests -parallel-testing-enabled NO -resultBundlePath "$PROJECT_ROOT/release/native-ui.xcresult" CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES "$ACCEPTANCE_FLAGS" || UI_EXIT=$?
finish_capture
GALLERY_EXIT=0
python3 "$PROJECT_ROOT/scripts/export-native-gallery.py" || GALLERY_EXIT=$?
[[ "$UNIT_EXIT" == 0 && "$UI_EXIT" == 0 && "$GALLERY_EXIT" == 0 ]] || { echo "Native checks failed: unit=$UNIT_EXIT UI=$UI_EXIT gallery=$GALLERY_EXIT; inspect actual artifacts." >&2; exit 1; }
python3 "$PROJECT_ROOT/scripts/native-build-report.py"
