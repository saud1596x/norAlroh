"""Check current archive after deletion, including XCTest container relocation."""
import json
import pathlib
import subprocess
import sys
from recording_ui_evidence import execution, verify_removed
container = pathlib.Path(subprocess.check_output([
    "xcrun", "simctl", "get_app_container", sys.argv[1], "com.saud1596x.nooralruh", "data"
], text=True).strip())
proof = json.loads(pathlib.Path("release/recitation-app/recording-ui-fixture.json").read_text())
verify_removed(container, sys.argv[1], execution(), proof)
print("NOOR_UI_RECORDING_ARCHIVE_REMOVED_AND_NEIGHBOR_DOCUMENT_PRESERVED")
