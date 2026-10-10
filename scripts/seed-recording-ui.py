"""Validate the actual native fixture before UI testing; capture run-bound proof."""
import json
import pathlib
import subprocess
import sys
from recording_ui_evidence import execution, seed
container = pathlib.Path(subprocess.check_output([
    "xcrun", "simctl", "get_app_container", sys.argv[1], "com.saud1596x.nooralruh", "data"
], text=True).strip())
proof = seed(container, sys.argv[1], execution())
output = pathlib.Path("release/recitation-app/recording-ui-fixture.json")
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps(proof, indent=2))
print("NOOR_UI_REFERENCE_VALIDATED:", proof["relativeRoot"], proof["audioSHA256"])
