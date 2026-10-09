"""Validate the native test's identified reference fixture before UI testing.
No path guessing, microphone capture or recognition results are fabricated.
"""
import json
import pathlib
import subprocess
import sys

container = pathlib.Path(subprocess.check_output([
    "xcrun", "simctl", "get_app_container", sys.argv[1], "com.saud1596x.nooralruh", "data"
], text=True).strip())
marker = container / "Documents/noor-ui-archive-path.txt"
root = pathlib.Path(marker.read_text().strip())
# The marker must point into this exact installed app's data container.
root.resolve().relative_to(container.resolve())
session = "A1662B68-55BB-4A4B-9441-761EF83DCF54"
take = "50CC9A34-A7A3-44B5-A7A7-39671AC60968"
folder = root / session
assert (folder / "session.json").is_file(), "Native reference header is missing"
assert (folder / (take + ".caf")).stat().st_size > 0, "Native reference audio is missing"
print("NOOR_UI_REFERENCE_VALIDATED:", folder)
output = pathlib.Path("release/recitation-app/recording-ui-fixture.json")
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps({
    "session": session, "take": take, "source": "112001.mp3", "repetitions": 20,
    "purpose": "Actual recording transport, restoration and relaunch UI checks",
    "createdBy": "Native AVAudioFile and production MushafRecordingArchive.root",
    "liveMicrophone": False, "automaticRecognitionResults": False
}, indent=2))
