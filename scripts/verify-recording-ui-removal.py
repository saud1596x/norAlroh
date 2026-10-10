"""Check the real seeded archive after the explicit Settings deletion journey."""
import pathlib
import subprocess
import sys

container = pathlib.Path(subprocess.check_output([
    "xcrun", "simctl", "get_app_container", sys.argv[1], "com.saud1596x.nooralruh", "data"
], text=True).strip())
marker = container / "Documents/noor-ui-archive-path.txt"
root = pathlib.Path(marker.read_text().strip())
root.resolve().relative_to(container.resolve())
assert not root.exists(), "Settings reported deletion but the seeded recording archive remains"
assert marker.is_file(), "Unrelated document was removed along with the recording archive"
print("NOOR_UI_RECORDING_ARCHIVE_REMOVED_AND_NEIGHBOR_DOCUMENT_PRESERVED")
