#!/usr/bin/env python3
"""Prepare the pinned offline Quran ASR model before Xcode project generation.

The runtime never downloads executable code or substitutes a different model.
Every byte is checked against the reviewed manifest, including cached files.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]


def verified(path, entry):
    if not path.is_file() or path.stat().st_size != entry["bytes"]:
        return False
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest() == entry["sha256"]


def prepare(output, cache=None, offline=False):
    manifest = json.loads((ROOT / "content-sources/recitation-model-manifest.json").read_text())
    assert manifest["schema"] == 1
    for entry in manifest["files"]:
        relative = Path(entry["path"])
        if relative.is_absolute() or ".." in relative.parts or relative.parts[0] not in {"model", "tokenizer"}:
            raise ValueError("Invalid model path")
        destination = output / relative
        if verified(destination, entry):
            continue
        destination.parent.mkdir(parents=True, exist_ok=True)
        fd, temporary = tempfile.mkstemp(prefix=".preparing-", dir=destination.parent)
        temporary = Path(temporary)
        try:
            with os.fdopen(fd, "wb") as target:
                source = cache / relative if cache else None
                if source and verified(source, entry):
                    with source.open("rb") as data:
                        shutil.copyfileobj(data, target)
                elif offline:
                    raise RuntimeError(f"Missing verified offline model file: {relative}")
                else:
                    if not entry["url"].startswith("https://huggingface.co/"):
                        raise ValueError("Unexpected model source")
                    with urllib.request.urlopen(entry["url"], timeout=90) as data:
                        shutil.copyfileobj(data, target)
                target.flush()
                os.fsync(target.fileno())
            if not verified(temporary, entry):
                raise RuntimeError(f"Model integrity check failed: {relative}")
            temporary.replace(destination)
        finally:
            temporary.unlink(missing_ok=True)
    shutil.copyfile(ROOT / "docs/WHISPER-MODEL-LICENSE.txt", output / "Whisper-LICENSE.txt")
    shutil.copyfile(ROOT / "docs/TARTEEL-MODEL-LICENSE.txt", output / "Tarteel-LICENSE.txt")
    shutil.copyfile(ROOT / "docs/RECITATION-MODEL-NOTICE.txt", output / "NOTICE.txt")
    print(f"Verified {len(manifest['files'])} pinned offline recognition resources.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "ios/RecitationModel")
    parser.add_argument("--cache", type=Path)
    parser.add_argument("--offline", action="store_true")
    args = parser.parse_args()
    prepare(args.output, args.cache, args.offline)
