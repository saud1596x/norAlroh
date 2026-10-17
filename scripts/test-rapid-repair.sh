#!/usr/bin/env bash
# Fast diagnosis of the current failures. This is not the Release publication gate.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p release/rapid-repair
python3 scripts/select-xcode.py > release/rapid-repair/xcode.env
source release/rapid-repair/xcode.env
export DEVELOPER_DIR
python3 - <<'PY'
import json,subprocess,time
from pathlib import Path
Path('release/rapid-repair/context.json').write_text(json.dumps({
    'sourceCommit':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),
    'startedUnix':time.time(),'configuration':'Debug',
    'scope':'Targeted failure reproduction; not complete Release, voice accuracy or physical device acceptance'
},indent=2)+'\n')
PY
xcodegen generate --spec ios/project.yml --project ios
# The captured host stack waited in HALC_ProxyObject::SetPropertyData while
# creating the output IOProc. Recover the audio daemon once on this disposable
# Codemagic worker, before starting its simulator. Never run this on a local Mac.
if [[ -n "${CM_BUILD_ID:-}" ]]; then
  python3 - <<'PYAUDIO'
import json,subprocess,time
from pathlib import Path
report={'scope':'Disposable Codemagic worker only; not an app fix or voice accuracy evidence'}
result=subprocess.run(['sudo','-n','killall','coreaudiod'],capture_output=True,text=True,timeout=10)
report['daemonRestartExit']=result.returncode
report['daemonRestartDiagnostic']=result.stderr[-500:]
time.sleep(2)
started=time.monotonic()
try:
    played=subprocess.run(['/usr/bin/afplay','ios/AtharTests/RecitationFixtures/112001.mp3'],capture_output=True,text=True,timeout=10)
    report.update(hostPlaybackExit=played.returncode,hostPlaybackDiagnostic=played.stderr[-1500:])
except subprocess.TimeoutExpired:
    report['hostPlaybackTimeout']=True
report['hostPlaybackElapsedSeconds']=time.monotonic()-started
Path('release/rapid-repair/host-playback.json').write_text(json.dumps(report,indent=2)+'\n')
print('ACTUAL_HOST_AUDIO',json.dumps(report))
PYAUDIO
fi
device=$(python3 - <<'PY'
import json,subprocess,os
from pathlib import Path
devices=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','--json']))
required_runtime=os.environ.get('NOOR_RAPID_RUNTIME')
phones=[(runtime,d) for runtime,rows in devices['devices'].items()
        if 'SimRuntime.iOS' in runtime and (not required_runtime or runtime == required_runtime) for d in rows
        if d.get('isAvailable') and d['name'].startswith('iPhone') and 'Pro Max' not in d['name']]
assert phones,f'An available iPhone Simulator is required for {required_runtime or "iOS"}; do not silently substitute runtimes'
runtime,phone=phones[0]
path=Path('release/rapid-repair/context.json');context=json.loads(path.read_text())
context.update(simulatorRuntime=runtime,simulatorName=phone['name'],simulatorUDID=phone['udid'])
path.write_text(json.dumps(context,indent=2)+'\n')
print(phone['udid'])
PY
)
cat release/rapid-repair/context.json
state=$(xcrun simctl list devices available --json | python3 -c 'import json,sys; print(next(x["state"] for rows in json.load(sys.stdin)["devices"].values() for x in rows if x["udid"]==sys.argv[1]))' "$device")
if [[ "$state" != Booted ]]; then xcrun simctl boot "$device"; fi
xcrun simctl bootstatus "$device" -b
# The prior headless run aborted inside AURemoteIO initialization. Launch the
# actual Simulator application as a controlled host-audio retry, without PCM substitution.
open -a Simulator --args -CurrentDeviceUDID "$device"
system_profiler SPAudioDataType -json > release/rapid-repair/host-audio.json
common=(-project ios/Athar.xcodeproj -scheme Athar -configuration Debug
  -destination "platform=iOS Simulator,id=$device"
  -derivedDataPath release/rapid-derived-data CODE_SIGNING_ALLOWED=NO
  ENABLE_TESTABILITY=YES ONLY_ACTIVE_ARCH=YES -parallel-testing-enabled NO
  'OTHER_SWIFT_FLAGS=$(inherited) -DNOOR_ACCEPTANCE_TESTING')
collect_failure_reports() {
  # Only this disposable build machine and this app's crash reports. No user's
  # device, audio, credentials or unrelated process logs are collected.
  mkdir -p release/rapid-repair/crashes
  python3 - <<'PYCRASH'
from pathlib import Path
import shutil,json
out=Path('release/rapid-repair/crashes')
files=[]
for folder in [Path.home()/'Library/Logs/DiagnosticReports', Path.home()/'Library/Logs/CrashReporter']:
    if not folder.exists(): continue
    for p in folder.glob('Athar*'):
        if p.is_file() and p.suffix in {'.ips','.crash'} and p.stat().st_size < 5_000_000:
            shutil.copyfile(p,out/p.name);files.append(p.name)
(out/'inventory.json').write_text(json.dumps(files,indent=2)+'\n')
for p in out.glob('*.ips'):
    try:
        text=p.read_text(); lines=text.splitlines(); data=json.loads('\n'.join(lines[1:]))
        print('ACTUAL_APP_CRASH', p.name, json.dumps({k:data.get(k) for k in ['exception','termination','faultingThread']},ensure_ascii=False))
        threads=data.get('threads',[])
        for thread in threads:
            if thread.get('triggered'): print('CRASH_FRAMES',json.dumps(thread.get('frames',[])[:18]))
    except (ValueError,OSError): pass
PYCRASH
}
trap collect_failure_reports EXIT
xcodebuild build-for-testing "${common[@]}"
# Capture the actual blocked thread while the reference test is still alive.
# Existing timeouts and assertions remain unchanged, and sampling never feeds
# samples or completion events into the player or microphone.
python3 scripts/sample-test-audio-hang.py "$device" release/rapid-repair/stacks &
audio_sampler=$!
audio_exit=0
xcodebuild test-without-building "${common[@]}" \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 60 \
  -maximum-test-execution-time-allowance 90 \
  -only-testing:AtharTests/QuranAudioBackendControlTests \
  -only-testing:AtharTests/LegacyRecordingFocusTests \
  -only-testing:AtharTests/MushafRecordingTests/testFailedRealDecodeReleasesOnlyOwnedAudioSessionWithoutDeletingBytes \
  -only-testing:AtharTests/MushafRecordingTests/testFailedDeactivationCanRetryWithoutReactivatingOrReplacingAudio \
  -only-testing:AtharTests/MushafRecordingTests/testFailedDeactivationCannotRetryAfterAnotherRecordingTakesOver \
  -only-testing:AtharTests/QuranMicrophoneInputLifecycleTests \
  -only-testing:AtharTests/QuranGuidedPracticeTests \
  -only-testing:AtharTests/QuranRecognitionWorkerLifecycleTests \
  -only-testing:AtharTests/QuranWordingAssessmentTests \
  -only-testing:AtharTests/QuranRecognitionAudioTests \
  -resultBundlePath release/rapid-repair/audio-lifecycle.xcresult || audio_exit=$?
kill "$audio_sampler" 2>/dev/null || true
wait "$audio_sampler" 2>/dev/null || true
if [[ "$audio_exit" != 0 ]]; then
  python3 - <<'PYSTACK'
from pathlib import Path
for p in sorted(Path('release/rapid-repair/stacks').glob('*.txt')):
    text = p.read_text(errors='replace')
    print('ACTUAL_AUDIO_STACK', p.name, text[:18000])
PYSTACK
  exit "$audio_exit"
fi
# Run the exact failing walkthrough first, without waiting for unrelated unit
# suites or a second physical-device archive. Keep its original assertions.
navigation_exit=not-run
if [[ "${NOOR_RAPID_NAVIGATION:-1}" == 1 ]]; then
  navigation_exit=0
  xcrun simctl privacy "$device" reset microphone com.saud1596x.nooralruh
  xcodebuild test-without-building "${common[@]}" \
    -only-testing:AtharUITests/NoorAllScreensTests/testAllScreensWalkthrough \
    -resultBundlePath release/rapid-repair/navigation.xcresult || navigation_exit=$?
fi
microphone_exit=0
xcrun simctl privacy "$device" grant microphone com.saud1596x.nooralruh
xcodebuild test-without-building "${common[@]}" \
  -only-testing:AtharUITests/NoorMushafStudyUITests \
  -resultBundlePath release/rapid-repair/microphone.xcresult || microphone_exit=$?
python3 - "$navigation_exit" "$microphone_exit" <<'PY'
import json,sys,time
from pathlib import Path
p=Path('release/rapid-repair/context.json'); data=json.loads(p.read_text())
data.update(finishedUnix=time.time(),navigationExit=None if sys.argv[1]=="not-run" else int(sys.argv[1]),microphoneExit=int(sys.argv[2]))
data['elapsedSeconds']=data['finishedUnix']-data['startedUnix']
p.write_text(json.dumps(data,indent=2)+'\n')
PY
[[ ( "$navigation_exit" == 0 || "$navigation_exit" == not-run ) && "$microphone_exit" == 0 ]]
