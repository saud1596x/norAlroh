"""Bind recording removal evidence to this run and a validated app-relative root."""
import hashlib
import os
import pathlib

ROOT = pathlib.Path("Library/Application Support/NoorMushafRecordings")
MARKER = pathlib.Path("Documents/noor-ui-archive-path.txt")
SESSION = "A1662B68-55BB-4A4B-9441-761EF83DCF54"
TAKE = "50CC9A34-A7A3-44B5-A7A7-39671AC60968"


def execution():
    keys = ("GITHUB_SHA", "GITHUB_RUN_ID", "GITHUB_RUN_ATTEMPT", "GITHUB_JOB", "NOOR_DISPLAY_CLASS")
    identity = {key: os.environ.get(key, "") for key in keys}
    if any(not identity[key] for key in keys):
        raise ValueError("Recording evidence requires the current GitHub execution identity")
    return identity


def digest(data):
    return hashlib.sha256(data).hexdigest()


def marker_root(container, data):
    if not container.is_absolute():
        raise ValueError("App container must be absolute")
    root = pathlib.Path(data.decode("utf-8").strip())
    if not root.is_absolute() or ".." in root.parts:
        raise ValueError("Archive marker must be an absolute path without traversal")
    if root.relative_to(container) != ROOT:
        raise ValueError("Archive marker is not the production recording root")
    root.resolve().relative_to(container.resolve())
    return root


def seed(container, simulator, identity):
    marker_bytes = (container / MARKER).read_bytes()
    root = marker_root(container, marker_bytes)
    folder = root / SESSION
    header = (folder / "session.json").read_bytes()
    audio = (folder / (TAKE + ".caf")).read_bytes()
    if not header or not audio:
        raise ValueError("Native reference header or audio is empty")
    return {
        "schemaVersion": 2, "containerAtSeed": str(container),
        "relativeRoot": ROOT.as_posix(), "markerSHA256": digest(marker_bytes),
        "markerValue": marker_bytes.decode("utf-8"), "simulator": simulator,
        "execution": identity, "session": SESSION, "take": TAKE,
        "audioSHA256": digest(audio), "audioBytes": len(audio),
        "metadataSHA256": digest(header), "source": "112001.mp3", "repetitions": 20,
        "createdBy": "Native AVAudioFile and production MushafRecordingArchive.root",
        "liveMicrophone": False, "automaticRecognitionResults": False,
    }


def verify_removed(container, simulator, identity, proof):
    if proof.get("schemaVersion") != 2 or proof.get("relativeRoot") != ROOT.as_posix():
        raise ValueError("Unsupported archive evidence")
    if proof.get("execution") != identity or proof.get("simulator") != simulator:
        raise ValueError("Stale or unrelated recording evidence")
    if proof.get("session") != SESSION or proof.get("take") != TAKE or proof.get("audioBytes", 0) <= 0:
        raise ValueError("Seeded native fixture proof is missing")
    for key in ("audioSHA256", "metadataSHA256"):
        value = proof.get(key, "")
        if len(value) != 64 or any(c not in "0123456789abcdef" for c in value):
            raise ValueError("Invalid fixture hash")
    marker_bytes = (container / MARKER).read_bytes()
    if digest(marker_bytes) != proof.get("markerSHA256") or marker_bytes.decode("utf-8") != proof.get("markerValue"):
        raise ValueError("The preserved marker differs from the validated seed")
    # Validate the original absolute marker before rebasing its exact known relative path.
    marker_root(pathlib.Path(proof["containerAtSeed"]), marker_bytes)
    root = container / ROOT
    if not container.is_absolute():
        raise ValueError("Current app container must be absolute")
    root.resolve().relative_to(container.resolve())
    if root.exists() or root.is_symlink():
        raise ValueError("Settings reported deletion but the current recording archive remains")
