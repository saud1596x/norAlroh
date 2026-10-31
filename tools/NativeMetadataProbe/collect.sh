#!/usr/bin/env bash
# Build metadata only. Never executes the fixture or claims Noor acceptance.
set -euo pipefail
cd "$(dirname "$0")/../.."
[[ "$(git rev-parse HEAD)" == "$GITHUB_SHA" ]]
root=release/native-xctestrun-probe
[[ ! -e "$root" ]] || { echo 'Refusing to overwrite previous metadata probe'; exit 2; }
fixture="$root/fixture"
out="$root/evidence"
derived="$root/derived"
mkdir -p "$fixture/App" "$fixture/UnitTests" "$fixture/UITests" "$out"
cat > "$fixture/App/AppDelegate.swift" <<'SWIFT'
import UIKit
@main final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let value = UIWindow(frame: UIScreen.main.bounds)
        value.rootViewController = UIViewController()
        window = value
        value.makeKeyAndVisible()
        return true
    }
}
SWIFT
cat > "$fixture/UnitTests/MetadataTests.swift" <<'SWIFT'
import XCTest
final class MetadataTests: XCTestCase {
    func testConfigurationOnly() { XCTAssertTrue(true) }
}
SWIFT
cat > "$fixture/UITests/MetadataUITests.swift" <<'SWIFT'
import XCTest
final class MetadataUITests: XCTestCase {
    func testConfigurationOnly() { XCTAssertTrue(true) }
}
SWIFT
cat > "$fixture/project.yml" <<'YAML'
name: NativeMetadataProbe
options:
  deploymentTarget:
    iOS: "17.0"
settings:
  base:
    SWIFT_VERSION: "5.0"
    GENERATE_INFOPLIST_FILE: YES
    TARGETED_DEVICE_FAMILY: "1,2"
    CODE_SIGNING_ALLOWED: NO
targets:
  NativeMetadataProbe:
    type: application
    platform: iOS
    sources: [App]
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.example.noor-native-metadata-probe
  ProbeUnitTests:
    type: bundle.unit-test
    platform: iOS
    sources: [UnitTests]
    dependencies:
      - target: NativeMetadataProbe
  ProbeUITests:
    type: bundle.ui-testing
    platform: iOS
    sources: [UITests]
    dependencies:
      - target: NativeMetadataProbe
schemes:
  NativeMetadataProbe:
    build:
      targets:
        NativeMetadataProbe: all
        ProbeUnitTests: [test]
        ProbeUITests: [test]
    test:
      targets: [ProbeUnitTests, ProbeUITests]
YAML
xcodegen generate --spec "$fixture/project.yml" --project "$fixture" 2>&1 | tee "$out/project-generation.txt"
build_exit=0
python3 scripts/run-native-with-deadline.py --build 300 xcodebuild build-for-testing \
 -project "$fixture/NativeMetadataProbe.xcodeproj" -scheme NativeMetadataProbe -configuration Release \
 -destination 'generic/platform=iOS Simulator' -derivedDataPath "$derived" \
 CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES ONLY_ACTIVE_ARCH=YES ARCHS=arm64 \
 -parallel-testing-enabled NO 'OTHER_SWIFT_FLAGS=$(inherited) -DNOOR_ACCEPTANCE_TESTING' \
 2>&1 | tee "$out/build.txt" || build_exit=$?
python3 - "$derived/Build/Products" "$out" "$build_exit" <<'PY'
import hashlib
import json
import os
from pathlib import Path
import plistlib
import platform
import shutil
import subprocess
import sys

products, output = Path(sys.argv[1]).resolve(), Path(sys.argv[2])
def command(*args):
    return subprocess.check_output(args, text=True).strip()
def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()
def write(name, value):
    (output / name).write_text(json.dumps(value, indent=2, sort_keys=True) + '\n', encoding='utf-8')

developer = os.environ['DEVELOPER_DIR']
context = {
    'scope': 'SDK_GENERATED_CONFIGURATION_PROBE_ONLY_NOT_NOOR_BUILD_OR_TEST_ACCEPTANCE',
    'sourceCommit': os.environ['GITHUB_SHA'], 'producerRunID': os.environ['GITHUB_RUN_ID'],
    'buildExitCode': int(sys.argv[3]), 'buildDeadlineSeconds': 300,
    'testsExecuted': False, 'appLaunched': False,
    'developerDirectory': developer, 'xcode': command('xcodebuild', '-version'),
    'sdkVersion': command('xcrun', '--sdk', 'iphonesimulator', '--show-sdk-version'),
    'sdkBuildVersion': command('xcrun', '--sdk', 'iphonesimulator', '--show-sdk-build-version'),
    'sdkPath': command('xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path'),
    'architecture': platform.machine(), 'macOSVersion': command('sw_vers', '-productVersion'),
    'macOSBuildVersion': command('sw_vers', '-buildVersion'),
}
originals, observations, libraries = [], [], []
runs = sorted(products.glob('*.xctestrun'))
for index, path in enumerate(runs):
    copied = output / ('original-%d-' % index + path.name)
    shutil.copyfile(path, copied)
    originals.append({'file': copied.name, 'sha256': digest(path), 'bytes': path.stat().st_size})
    def inspect(value, trail=(), environment=False):
        if isinstance(value, dict):
            for key, child in value.items():
                inspect(child, trail + (str(key),), environment or key.endswith('EnvironmentVariables'))
        elif isinstance(value, list):
            for item_index, child in enumerate(value):
                inspect(child, trail + (str(item_index),), environment)
        elif isinstance(value, str):
            key = trail[-1] if trail else ''
            relevant = (key.endswith(('Path', 'Paths')) or value.startswith(('/', '__')) or
                        (environment and (key.startswith(('DYLD_', 'XCInject', 'XCTest')) or '/' in value)))
            if relevant:
                observations.append({'originalFile': copied.name, 'plistPath': list(trail), 'value': value})
            if key == 'DYLD_INSERT_LIBRARIES':
                for component in value.split(':'):
                    resolved = component.replace('__PLATFORMS__', developer + '/Platforms').replace('__TESTROOT__', str(products))
                    library = Path(resolved)
                    record = {'originalValue': component, 'resolvedForInspectionOnly': resolved,
                              'existsOnBuildHost': library.is_file()}
                    if library.is_file():
                        record.update(sha256=digest(library), bytes=library.stat().st_size,
                                      realPath=str(library.resolve()))
                        probe = subprocess.run(['xcrun', 'lipo', '-archs', str(library)],
                                               capture_output=True, text=True, timeout=10)
                        record.update(lipoExitCode=probe.returncode, architectures=probe.stdout.strip())
                    libraries.append(record)
    inspect(plistlib.loads(path.read_bytes()))
context['originalXctestrunFiles'] = originals
write('context.json', context)
write('generated-path-environment-values.json', observations)
write('generated-injection-library-observations.json', libraries)
print(json.dumps({'scope': context['scope'], 'originalXctestrunCount': len(originals),
                  'buildExitCode': context['buildExitCode'], 'testsExecuted': False, 'appLaunched': False}))
if int(sys.argv[3]) == 0 and len(runs) != 1:
    raise SystemExit('Expected exactly one original generated xctestrun')
PY
exit "$build_exit"
