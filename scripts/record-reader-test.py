"""Record the real Simulator UI journey, not a generated demonstration.

Starts only when XCTest actually starts the reader UI suite. No microphone,
recognition accuracy or frame-rate acceptance is inferred from this recording.
"""
import json, os, signal, subprocess, sys, time
from pathlib import Path

device, log_name, folder = sys.argv[1:]
root = Path(folder); log = Path(log_name); stop = root / 'test-finished'
running = True
def terminate(*_):
    global running
    running = False
signal.signal(signal.SIGTERM, terminate)
signal.signal(signal.SIGINT, terminate)
process = None; handle = None
offset = 0; tail = ''
started = time.monotonic()
try:
    while running and not stop.exists() and time.monotonic() - started < 650:
        if log.exists():
            with log.open(errors='replace') as stream:
                stream.seek(offset); tail = (tail + stream.read())[-8192:]; offset = stream.tell()
        text = tail
        if process is None and "Test Suite 'NoorContinuousReaderUITests' started" in text:
            handle = (root / 'video-log.txt').open('w')
            process = subprocess.Popen(['xcrun', 'simctl', 'io', device, 'recordVideo', '--codec=h264',
                str(root / 'native-reader-journey.mp4')], stdout=handle, stderr=handle, start_new_session=True)
        if process is not None and ("Test Suite 'NoorContinuousReaderUITests' passed" in text or "Test Suite 'NoorContinuousReaderUITests' failed" in text): break
        time.sleep(0.25)
finally:
    if process is not None and process.poll() is None:
        os.killpg(process.pid, signal.SIGINT)
        try: process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL); process.wait()
    if handle: handle.close()
    video = root / 'native-reader-journey.mp4'
    (root / 'video-status.json').write_text(json.dumps({'scope':'Actual UI journey only; not device microphone or recognition-quality evidence',
        'started':process is not None, 'exit':process.returncode if process else None,
        'bytes':video.stat().st_size if video.exists() else 0}) + '\n')
