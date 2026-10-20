#!/usr/bin/env bash
# Actual Release reader evidence. Does not certify ASR, learner or Tajweed accuracy.
set -euo pipefail
cd "$(dirname "$0")/.."
size=${1:?Exact small, medium or large display class required}
case "$size" in small|medium|large) ;; *) echo 'Invalid requested display class'; exit 2;; esac
out="release/mushaf-closure/$size"
mkdir -p "$out"
python3 scripts/check-native-test-selectors.py scripts/test-mushaf-closure.sh
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
# project-accounts includes project.yml's verified resource preGenCommand.
# Keep the full application resources and extensions for the actual Release UI.
xcodegen generate --spec ios/project-accounts.yml --project ios 2>&1 | tee "$out/project-generation.txt"
derived="release/mushaf-closure-derived-$size"
common=(-project ios/Athar.xcodeproj -scheme Athar -configuration Release
 -destination "platform=iOS Simulator,id=$device" -derivedDataPath "$derived"
 CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES ONLY_ACTIVE_ARCH=YES
 -parallel-testing-enabled NO 'OTHER_SWIFT_FLAGS=$(inherited) -DNOOR_ACCEPTANCE_TESTING')
build_exit=0
python3 scripts/run-native-with-deadline.py --build 1200 xcodebuild build-for-testing "${common[@]}" 2>&1 | tee "$out/build.txt" || build_exit=$?
python3 scripts/verify-mushaf-closure-evidence.py command --output-dir "$out" --lane build --exit-code "$build_exit" --deadline 1200
[[ "$build_exit" == 0 ]] || exit "$build_exit"
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
 run_case geometry 600 180 \
  -only-testing:AtharTests/InteractiveMushafTests \
  -only-testing:AtharTests/MushafViewportTests \
  -only-testing:AtharTests/NoorContinuousMushafTests/testOriginalTajweedLayersRenderAll604PagesAndPreserveHiddenWordGeometry \
  -only-testing:AtharTests/NoorContinuousMushafTests/testOriginalTajweedPaletteUsesRequestedCanvasStyleDespiteOppositeAmbientTraits
 # This existing test retains its original 120s XCTest maximum and 180s process budget.
 run_case reader-library 180 120 -only-testing:AtharUITests/NoorReciterLibraryTests
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
 run_case "gallery-special-$look" 180 120 \
  -only-testing:AtharUITests/NoorMushafClosureUITests/testReferenceSpecialAndFinalPagesKeepGeometry
 run_case "controls-$look" 180 120 \
  -only-testing:AtharUITests/NoorMushafClosureUITests/testTajweedFullscreenAndAyahActionsKeepGeometry
 run_case "large-text-$look" 180 120 \
  -only-testing:AtharUITests/NoorMushafClosureUITests/testLargeInterfaceTextKeepsControlsOutsideTheQuran
done
trap - EXIT
python3 scripts/verify-mushaf-closure-evidence.py verify --output-dir "$out" --expected-size "$size" --expected-commit "$(git rev-parse HEAD)" --contact-sheets || failed=1
exit "$failed"
