#!/usr/bin/env bash
# Unsigned Simulator evidence for the reading-only product. No device, signing,
# audio-acoustic, physical WidgetKit delivery or full-release approval claim.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Darwin ]]
[[ "$(git rev-parse HEAD)" == "$GITHUB_SHA" ]]
[[ "$NATIVE_PRODUCER_RUN_ID" == "$GITHUB_RUN_ID" ]]
size=${1:?Exact small, large or services lane required}
case "$size" in small|large|services) ;; *) echo 'Unsupported verification lane'; exit 2;; esac
out="release/reading-only/$size"
[[ ! -e "$out" ]] || { echo 'Refusing to overwrite previous evidence'; exit 2; }
mkdir -p "$out"
python3 scripts/check-native-test-selectors.py scripts/test-reading-only.sh
artifact=release/mushaf-native-artifact
products="release/reading-only-products-$size"
xctestrun=$(python3 scripts/native-product-artifact.py unpack --artifact "$artifact" --destination "$products")
cp "$artifact/manifest.json" "$out/manifest.json"
cp "$products/producer/commands.json" "$out/producer-commands.json"
xcodebuild -version > "$out/xcode.txt"
git rev-parse HEAD > "$out/source.txt"
xcrun simctl list devicetypes --json > "$out/device-types.json"
xcrun simctl list runtimes --json > "$out/runtimes.json"
xcrun simctl list devices available --json > "$out/devices.json"
device=$(python3 - "$out" "$size" <<'PY'
import json,os,re,subprocess,sys
from pathlib import Path
out=Path(sys.argv[1]); size=sys.argv[2]
read=lambda name: json.loads((out/name).read_text())
identifier={'small':'com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation',
            'services':'com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation',
            'large':'com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max'}[size]
kind=next((v for v in read('device-types.json')['devicetypes'] if v['identifier']==identifier),None)
assert kind, 'Exact requested simulator type unavailable; no device substitution'
runtimes=[r for r in read('runtimes.json')['runtimes'] if r.get('isAvailable') and r['identifier'].startswith('com.apple.CoreSimulator.SimRuntime.iOS-26-')]
assert runtimes, 'An available iOS26 runtime is required'
reference=[r for r in runtimes if r['version'].split('.')[:2]==['26','2']]
runtime=max(reference or runtimes,key=lambda r:tuple(map(int,r['version'].split('.'))))
devices=[d for d in read('devices.json')['devices'].get(runtime['identifier'],[]) if d.get('isAvailable') and d.get('deviceTypeIdentifier')==identifier]
device=devices[0]['udid'] if devices else subprocess.check_output(['xcrun','simctl','create','Noor reading-only '+size,identifier,runtime['identifier']],text=True).strip()
assert re.fullmatch(r'[A-Fa-f0-9-]{36}',device)
context={'sourceCommit':os.environ['GITHUB_SHA'],'producerRunID':os.environ['GITHUB_RUN_ID'],
 'configuration':'Release','project':'project-accounts.yml','size':size,'deviceName':kind['name'],
 'deviceUDID':device,'runtime':runtime['identifier'],'runtimeVersion':runtime['version'],
 'manifestSHA256':os.environ['NATIVE_MANIFEST_SHA256'],'archiveSHA256':os.environ['NATIVE_ARCHIVE_SHA256'],
 'verifiedBeforeTesting':True,'verifiedAfterTesting':False,
 'scope':'SELECTED_READING_ONLY_SIMULATOR_TESTS_NOT_DEVICE_OR_PUBLICATION_ACCEPTANCE'}
(out/'context.json').write_text(json.dumps(context,indent=2)+'\n')
print(device)
PY
)
python3 - "$device" <<'PY'
import subprocess,sys
subprocess.run(['xcrun','simctl','bootstatus',sys.argv[1],'-b'],check=True,timeout=240)
PY
xcrun simctl io "$device" screenshot --type=png "$out/actual-display.png"
common=(-xctestrun "$xctestrun" -destination "platform=iOS Simulator,id=$device" -parallel-testing-enabled NO)
failed=0
video_pid=''
stop_video() {
 if [[ -n "$video_pid" ]]; then
  touch "$out/video-light-stop"
  wait "$video_pid" || failed=1
  video_pid=''
 fi
}
trap stop_video EXIT
run_lane() {
 local lane=$1 deadline=$2 maximum=$3; shift 3
 local result=0
 # Derive the exact requested methods before execution, then require each in
 # the original xcresult. A zero-test, skipped or partial pass is rejected.
 python3 - "$out" "$lane" "$@" <<'PY'
import importlib.util,json,sys
from pathlib import Path
spec=importlib.util.spec_from_file_location('selectors','scripts/check-native-test-selectors.py')
module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
suites=module.inventory(); expected=[]
for arg in sys.argv[3:]:
 if not arg.startswith('-only-testing:'): raise SystemExit('Only explicit test selectors are allowed')
 parts=arg.split(':',1)[1].split('/'); bundle,suite=parts[:2]
 methods=[parts[2]] if len(parts)==3 else sorted(suites[bundle][suite])
 for method in methods:
  assert method in suites[bundle][suite]
  expected.append(suite+'/'+method)
assert expected and len(expected)==len(set(expected))
(Path(sys.argv[1])/(sys.argv[2]+'-expected.json')).write_text(json.dumps(expected)+'\n')
PY
 python3 scripts/run-native-with-deadline.py "$deadline" xcodebuild test-without-building "${common[@]}" \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 120 \
  -maximum-test-execution-time-allowance "$maximum" "$@" \
  -resultBundlePath "$out/$lane.xcresult" 2>&1 | \
  python3 scripts/verify-mushaf-closure-evidence.py log --output-dir "$out" --lane "$lane" || result=$?
 if [[ "$lane" == reading-journey ]]; then stop_video; fi
 python3 scripts/verify-mushaf-closure-evidence.py command --output-dir "$out" --lane "$lane" --exit-code "$result" --deadline "$deadline"
 python3 scripts/verify-mushaf-closure-evidence.py collect --output-dir "$out" --lane "$lane" || failed=1
 python3 - "$out" "$lane" <<'PY' || failed=1
import importlib.util,json,sys
from pathlib import Path
spec=importlib.util.spec_from_file_location('evidence','scripts/verify-mushaf-closure-evidence.py')
module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
out=Path(sys.argv[1]); lane=sys.argv[2]
read=lambda name:json.loads((out/name).read_text())
assert read('commands.json')[lane]['exitCode']==0, 'Original command failed'
result=module.validate_tests(out,lane,read(lane+'-expected.json'),read('collection.json'))
if lane != 'services':
 attachments=out/(lane+'-attachments')
 assert any(attachments.rglob('*.png')), 'UI lane has no original screenshot attachments'
(out/(lane+'-verified.json')).write_text(json.dumps(result,indent=2)+'\n')
print(lane, result['passedTests'], 'original native cases passed')
PY
 [[ "$result" == 0 ]] || failed=1
}
# Services execute once; both display classes independently execute actual UI.
if [[ "$size" == services ]]; then
 run_lane services 900 180 \
  -only-testing:AtharTests/QuranAccuracyTests \
  -only-testing:AtharTests/InteractiveMushafTests \
  -only-testing:AtharTests/MushafViewportTests \
  -only-testing:AtharTests/NoorReciterWordTimingTests \
  -only-testing:AtharTests/NoorAdditionalReciterTests \
  -only-testing:AtharTests/MushafVerseAudioSeekTests \
  -only-testing:AtharTests/PublishingContentTests \
  -only-testing:AtharTests/LocalDataRecoveryTests \
  -only-testing:AtharTests/ReadingSyncTests \
  -only-testing:AtharTests/NoorAccountDeletionStateTests \
  -only-testing:AtharTests/KhatmahJourneyTests \
  -only-testing:AtharTests/WidgetTests \
  -only-testing:AtharTests/WidgetTimelineTests \
  -only-testing:AtharTests/FixedPrayerPolicyTests \
  -only-testing:AtharTests/NotificationReconciliationTests \
  -only-testing:AtharTests/NoorPersonalReminderTests \
  -only-testing:AtharTests/NoorSalawatTests
else
run_lane welcome-home 480 180 \
 -only-testing:AtharUITests/NoorLaunchTests \
 -only-testing:AtharUITests/NoorHomeFlowUITests \
 -only-testing:AtharUITests/NoorReadingOnlyUITests/testReducedMotionPreferenceSurvivesRelaunchAndReaderReturn
xcrun simctl ui "$device" appearance light
python3 scripts/verify-mushaf-closure-evidence.py record --output-dir "$out" --look light --device "$device" &
video_pid=$!
run_lane reading-journey 160 120 \
 -only-testing:AtharUITests/NoorReadingOnlyUITests/testReadingOptionsDoNotExposeCaptureOrTajweedAndCancelPreservesPage
run_lane reader 900 300 \
 -only-testing:AtharUITests/NoorReaderComfortUITests \
 -only-testing:AtharUITests/NoorReciterLibraryTests
run_lane navigation 600 300 \
 -only-testing:AtharUITests/NoorAllScreensTests \
 -only-testing:AtharUITests/NoorNavigationTests \
 -only-testing:AtharUITests/NoorFridayRetirementUITests
run_lane design 420 120 \
 -only-testing:AtharUITests/NoorTodayDesignUITests/testProductionTodayLight \
 -only-testing:AtharUITests/NoorTodayDesignUITests/testProductionTodayDark \
 -only-testing:AtharUITests/NoorTodayDesignUITests/testProductionTodayAccessibility
# A real ward changes saved Home state. Run its setup after ordinary reading.
run_lane ward-reminders 480 180 \
 -only-testing:AtharUITests/NoorReminderUITests \
 -only-testing:AtharUITests/NoorPrayerDisplayUITests \
 -only-testing:AtharUITests/NoorKhatmahUITests/testHomeContinuesOneTwentyPageWardAndKeepsStopInsideSameAction
fi
trap - EXIT
if python3 scripts/native-product-artifact.py check --artifact "$artifact" --destination "$products"; then
 python3 - "$out" "$failed" <<'PY'
import json,sys
from pathlib import Path
p=Path(sys.argv[1])/'context.json'; context=json.loads(p.read_text())
context['verifiedAfterTesting']=True
context['selectedLanesPassed']=sys.argv[2]=='0'
p.write_text(json.dumps(context,indent=2)+'\n')
PY
else
 failed=1
fi
exit "$failed"
