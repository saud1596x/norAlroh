"""Simulator-only transport fixture: repeated authentic reference audio.

No microphone capture or recognition results are fabricated. This fixture is
not full-session acceptance evidence and must be identified in exported media.
"""
import datetime
import json
import pathlib
import subprocess
import sys
import tempfile
import wave

device = sys.argv[1]
container = pathlib.Path(subprocess.check_output([
    "xcrun", "simctl", "get_app_container", device, "com.saud1596x.nooralruh", "data"
], text=True).strip())
session = "A1662B68-55BB-4A4B-9441-761EF83DCF54"
take = "50CC9A34-A7A3-44B5-A7A7-39671AC60968"
folder = container / "Library/Application Support/NoorMushafRecordings" / session
folder.mkdir(parents=True, exist_ok=True)
fixture = pathlib.Path("ios/AtharTests/RecitationFixtures/112001.mp3").resolve()
with tempfile.TemporaryDirectory(prefix="noor-playback-reference-") as temporary:
    short = pathlib.Path(temporary) / "reference.wav"
    repeated = pathlib.Path(temporary) / "repeated-reference.wav"
    subprocess.run(["afconvert", str(fixture), str(short), "-f", "WAVE", "-d", "LEI16@16000", "-c", "1"], check=True)
    with wave.open(str(short), "rb") as original:
        parameters, frames = original.getparams(), original.readframes(original.getnframes())
    with wave.open(str(repeated), "wb") as output:
        output.setparams(parameters)
        for _ in range(20):
            output.writeframes(frames)
    subprocess.run(["afconvert", str(repeated), str(folder / (take + ".caf")), "-f", "caff", "-d", "LEF32@16000", "-c", "1"], check=True)
epoch = datetime.datetime(2001, 1, 1, tzinfo=datetime.timezone.utc)
stamp = (datetime.datetime.now(datetime.timezone.utc) - epoch).total_seconds()
(folder / "session.json").write_text(json.dumps({
    "id": session, "startedAt": stamp, "scope": "range", "keys": ["112:1"], "page": 604
}))
pathlib.Path("release/recitation-app/recording-ui-fixture.json").write_text(json.dumps({
    "session": session, "take": take, "source": "112001.mp3", "repetitions": 20,
    "purpose": "Actual recording transport, restoration and relaunch UI checks",
    "liveMicrophone": False, "automaticRecognitionResults": False
}, indent=2))
