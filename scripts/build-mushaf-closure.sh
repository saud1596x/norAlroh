#!/usr/bin/env bash
# Build once on the same standard public macOS architecture used by all sizes.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(git rev-parse HEAD)" == "$GITHUB_SHA" ]]
out=release/mushaf-closure-producer
mkdir -p "$out"
python3 scripts/check-native-test-selectors.py scripts/test-mushaf-closure.sh
xcodegen generate --spec ios/project-accounts.yml --project ios 2>&1 | tee "$out/project-generation.txt"
build_exit=0
python3 scripts/run-native-with-deadline.py --build 1200 xcodebuild build-for-testing \
 -project ios/Athar.xcodeproj -scheme Athar -configuration Release \
 -destination 'generic/platform=iOS Simulator' -derivedDataPath release/mushaf-closure-build \
 CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES ONLY_ACTIVE_ARCH=YES ARCHS=arm64 \
 -parallel-testing-enabled NO 'OTHER_SWIFT_FLAGS=$(inherited) -DNOOR_ACCEPTANCE_TESTING' \
 2>&1 | tee "$out/build.txt" || build_exit=$?
python3 scripts/verify-mushaf-closure-evidence.py command --output-dir "$out" --lane build --exit-code "$build_exit" --deadline 1200
[[ "$build_exit" == 0 ]] || exit "$build_exit"
python3 scripts/native-product-artifact.py pack --products release/mushaf-closure-build/Build/Products \
 --producer "$out" --output release/mushaf-native-artifact
