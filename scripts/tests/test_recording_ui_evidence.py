import pathlib
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from recording_ui_evidence import MARKER, ROOT, SESSION, TAKE, execution, seed, verify_removed


class RecordingEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = pathlib.Path(self.temp.name).resolve()
        self.original = self.base / "original"
        folder = self.original / ROOT / SESSION
        folder.mkdir(parents=True)
        (folder / "session.json").write_bytes(b'{"fixture":true}')
        (folder / (TAKE + ".caf")).write_bytes(b"test-payload")
        marker = self.original / MARKER
        marker.parent.mkdir(parents=True)
        marker.write_text(str(self.original / ROOT))
        self.identity = {
            "GITHUB_RUN_ID": "71", "GITHUB_RUN_ATTEMPT": "1", "GITHUB_SHA": "source",
            "GITHUB_JOB": "ios", "NOOR_DISPLAY_CLASS": "large",
        }
        self.proof = seed(self.original, "simulator", self.identity)

    def relocated(self):
        current = self.base / "current"
        shutil.copytree(self.original, current)
        shutil.rmtree(current / ROOT)
        return current

    def test_same_container_removed(self):
        shutil.rmtree(self.original / ROOT)
        verify_removed(self.original, "simulator", self.identity, self.proof)

    def test_relocated_container_removed(self):
        verify_removed(self.relocated(), "simulator", self.identity, self.proof)

    def test_relocated_existing_archive_rejected(self):
        current = self.relocated()
        (current / ROOT).mkdir(parents=True)
        with self.assertRaises(ValueError):
            verify_removed(current, "simulator", self.identity, self.proof)

    def test_changed_marker_rejected(self):
        current = self.relocated()
        (current / MARKER).write_text(str(current / ROOT))
        with self.assertRaises(ValueError):
            verify_removed(current, "simulator", self.identity, self.proof)

    def test_stale_execution_or_simulator_rejected(self):
        current = self.relocated()
        for simulator, identity in [("other", self.identity), ("simulator", {"run": "70"})]:
            with self.assertRaises(ValueError):
                verify_removed(current, simulator, identity, self.proof)

    def test_missing_execution_job_or_display_rejected(self):
        for key in ("GITHUB_JOB", "NOOR_DISPLAY_CLASS"):
            for value in (None, ""):
                identity = dict(self.identity)
                if value is None:
                    identity.pop(key)
                else:
                    identity[key] = value
                with self.subTest(key=key, value=value), patch.dict("os.environ", identity, clear=True):
                    with self.assertRaises(ValueError):
                        execution()

    def test_wrong_source_attempt_or_display_rejected(self):
        current = self.relocated()
        for key, value in (("GITHUB_SHA", "other-source"), ("GITHUB_RUN_ATTEMPT", "2"),
                           ("NOOR_DISPLAY_CLASS", "compact")):
            identity = dict(self.identity)
            identity[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                verify_removed(current, "simulator", identity, self.proof)

    def test_unrelated_or_traversing_marker_rejected(self):
        for path in [self.base / "unrelated", self.original / "Library/../foreign"]:
            (self.original / MARKER).write_text(str(path))
            with self.assertRaises(ValueError):
                seed(self.original, "simulator", self.identity)

    def test_current_symlink_escape_rejected(self):
        current = self.relocated()
        outside = self.base / "outside"
        outside.mkdir()
        try:
            (current / ROOT).symlink_to(outside, target_is_directory=True)
        except OSError:
            self.skipTest("Platform does not permit directory symlink creation")
        with self.assertRaises(ValueError):
            verify_removed(current, "simulator", self.identity, self.proof)


if __name__ == "__main__":
    unittest.main()
