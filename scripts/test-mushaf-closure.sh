#!/usr/bin/env bash
# Actual Release reader evidence. Does not certify ASR, learner or Tajweed accuracy.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(git rev-parse HEAD)" == "$GITHUB_SHA" ]]
size=${1:?Exact small, medium or large display class required}
case "$size" in small|medium|large) ;; *) echo 'Invalid requested display class'; exit 2;; esac
out="release/mushaf-closure/$size"
mkdir -p "$out"
python3 scripts/check-native-test-selectors.py scripts/test-mushaf-closure.sh
artifact=release/mushaf-native-artifact
products="release/mushaf-closure-products-$size"
xctestrun=$(python3 scripts/native-product-artifact.py unpack --artifact "$artifact" --destination "$products")
# Preserve the actual producer's bounded build, never synthesize a local build.
cp "$artifact/manifest.json" "$out/manifest.json"
cp "$products/producer/build.txt" "$out/build.txt"
cp "$products/producer/project-generation.txt" "$out/project-generation.txt"
cp "$products/producer/commands.json" "$out/producer-commands.json"
cp "$products/producer/commands.json" "$out/commands.json"
python3 - "$out" <<'PY'
import json, os, sys
from pathlib import Path
binding = {'producerRunID': os.environ['GITHUB_RUN_ID'],
           'manifestSHA256': os.environ['NATIVE_MANIFEST_SHA256'],
           'archiveSHA256': os.environ['NATIVE_ARCHIVE_SHA256'],
           'verifiedBeforeTesting': True, 'verifiedAfterTesting': False}
(Path(sys.argv[1]) / 'native-product-binding.json').write_text(json.dumps(binding) + '\n')
PY
xcodebuild -version > "$out/xcode.txt"
git rev-parse HEAD > "$out/source.txt"
xcrun simctl list devicetypes --json > "$out/device-types.json"
xcrun simctl list runtimes --json > "$out/runtimes.json"
xcrun simctl list devices available --json > "$out/devices.json"
device=$(python3 scripts/verify-mushaf-closure-evidence.py select --output-dir "$out" --expected-size "$size")
xcrun simctl boot "$device" || true
xcrun simctl bootstatus "$device" -b
xcrun simctl list devices available --json > "$out/actual-booted-devices.json"
open -a Simulator --args -CurrentDeviceUDID "$device"
xcrun simctl io "$device" screenshot --type=png "$out/actual-display.png"
common=(-xctestrun "$xctestrun" -destination "platform=iOS Simulator,id=$device"
 -parallel-testing-enabled NO)
failed=0
video_pid=''
video_look=''
stop_video() {
 if [[ -n "$video_pid" ]]; then
  touch "$out/video-$video_look-stop"
  wait "$video_pid" || failed=1
  video_pid=''
 fi
}
trap stop_video EXIT
run_case() {
 local name=$1 deadline=$2 maximum=$3; shift 3
 local result=0
 python3 scripts/run-native-with-deadline.py "$deadline" xcodebuild test-without-building "${common[@]}" \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 100 \
  -maximum-test-execution-time-allowance "$maximum" \
  "$@" -resultBundlePath "$out/$name.xcresult" 2>&1 | \
  python3 scripts/verify-mushaf-closure-evidence.py log --output-dir "$out" --lane "$name" || result=$?
 python3 scripts/verify-mushaf-closure-evidence.py command --output-dir "$out" --lane "$name" --exit-code "$result" --deadline "$deadline"
 # End the continuous journey recording before exporting xcresult. Export
 # work is not part of the user journey and must not consume its video guard.
 if [[ "$name" == journey-* ]]; then sleep 1; stop_video; fi
 # Collection failure stays a failure; export originals even after failed tests.
 python3 scripts/verify-mushaf-closure-evidence.py collect --output-dir "$out" --lane "$name" || failed=1
 [[ "$result" == 0 ]] || failed=1
}
if [[ "$size" == medium ]]; then
 run_case service-contracts 600 120 \
  -only-testing:AtharTests/FixedPrayerPolicyTests \
  -only-testing:AtharTests/NotificationReconciliationTests \
  -only-testing:AtharTests/NoorPersonalReminderTests \
  -only-testing:AtharTests/NoorSalawatTests \
  -only-testing:AtharTests/WidgetTests \
  -only-testing:AtharTests/WidgetTimelineTests \
  -only-testing:AtharTests/PublishingContentTests \
  -only-testing:AtharTests/KhatmahJourneyTests
 run_case recitation-contracts 600 120 \
  -only-testing:AtharTests/QuranMicrophoneInputLifecycleTests \
  -only-testing:AtharTests/QuranWindowMailboxTests \
  -only-testing:AtharTests/QuranLiveRecitationStorageTests \
  -only-testing:AtharTests/QuranRecognitionWorkerLifecycleTests
 run_case geometry 600 180 \
  -only-testing:AtharTests/InteractiveMushafTests \
  -only-testing:AtharTests/MushafViewportTests \
  -only-testing:AtharTests/NoorContinuousMushafTests/testOriginalTajweedLayersRenderAll604PagesAndPreserveHiddenWordGeometry \
  -only-testing:AtharTests/NoorContinuousMushafTests/testOriginalTajweedPaletteUsesRequestedCanvasStyleDespiteOppositeAmbientTraits
 # This existing test retains its original 120s XCTest maximum and 180s process budget.
 run_case reader-library 180 120 -only-testing:AtharUITests/NoorReciterLibraryTests
 run_case navigation-contracts 600 120 \
  -only-testing:AtharUITests/NoorHomeFlowUITests/testFourTabsAndVisibleOptionalAccountSurviveRelaunch \
  -only-testing:AtharUITests/NoorReminderUITests \
  -only-testing:AtharUITests/NoorPrayerDisplayUITests
fi
for look in light dark; do
 xcrun simctl ui "$device" appearance "$look"
 xcrun simctl ui "$device" appearance > "$out/appearance-$look.txt"
 # The original microphone tap must handle the real first OS permission prompt.
 xcrun simctl privacy "$device" reset microphone com.saud1596x.nooralruh
 video_look="$look"
 python3 scripts/verify-mushaf-closure-evidence.py record --output-dir "$out" --look "$look" --device "$device" &
 video_pid=$!
 sleep 1
 run_case "journey-$look" 180 180 \
  -only-testing:AtharUITests/NoorMushafClosureUITests/testMeasuredReadingJourneyKeepsGeometryAndSurvivesActualCapture
 # Independent original-UI captures keep coverage without inflating the core
 # journey's unchanged 180s process budget or concealing a failed lane.
 run_case "gallery-openings-$look" 180 120 \
  -only-testing:AtharUITests/NoorMushafClosureUITests/testReferenceOpeningAndDensePagesKeepGeometry
 run_case "gallery-dense-$look" 180 120 \
  -only-testing:AtharUITests/NoorMushafClosureUITests/testReferenceDenseAndTawbaPagesKeepGeometry
 run_case "gallery-special-$look" 180 120 \
  -only-testing:AtharUITests/NoorMushafClosureUITests/testReferenceSpecialAndFinalPagesKeepGeometry
 run_case "gallery-final-$look" 180 120 \
  -only-testing:AtharUITests/NoorMushafClosureUITests/testReferenceDebtAndFinalPagesKeepGeometry
 run_case "controls-$look" 180 120 \
  -only-testing:AtharUITests/NoorMushafClosureUITests/testTajweedFullscreenAndAyahActionsKeepGeometry
 run_case "large-text-$look" 180 120 \
  -only-testing:AtharUITests/NoorMushafClosureUITests/testLargeInterfaceTextKeepsControlsOutsideTheQuran
done
# These reading journeys do not create a Khatmah plan. Run the one real ward
# setup last on the medium job's fresh app data; its completed plan must not
# change the Home assumptions of the ordinary reading journeys above.
if [[ "$size" == medium ]]; then
 run_case ward-entry 180 120 \
  -only-testing:AtharUITests/NoorKhatmahUITests/testHomeContinuesOneTwentyPageWardAndKeepsStopInsideSameAction
fi
trap - EXIT
python3 scripts/native-product-artifact.py check --artifact "$artifact" --destination "$products"
python3 - "$out" <<'PY'
import json, sys
from pathlib import Path
path = Path(sys.argv[1]) / 'native-product-binding.json'
binding = json.loads(path.read_text())
binding['verifiedAfterTesting'] = True
path.write_text(json.dumps(binding) + '\n')
PY
python3 scripts/verify-mushaf-closure-evidence.py verify --output-dir "$out" --expected-size "$size" --expected-commit "$(git rev-parse HEAD)" --contact-sheets || failed=1
exit "$failed"
