#!/usr/bin/env python3
"""Fetch pinned, public investigation data; never ship a model as a validated grader."""
import argparse
import hashlib
import json
import random
import subprocess
import urllib.request
import wave
from pathlib import Path

from huggingface_hub import snapshot_download

MODEL = "fazalshaikh123/ultra-fast-tarteel-coreml"
MODEL_REVISION = "0338074ac8d662f6f52c5d66b433cac74202158e"
TOKENIZER_REVISION = "e37978b90ca9030d5170a5c07aadb050351a65bb"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    root = args.output.resolve()
    root.mkdir(parents=True, exist_ok=True)
    model = root / "model"
    tokenizer = root / "tokenizer"
    snapshot_download(MODEL, revision=MODEL_REVISION, local_dir=model,
                      allow_patterns=["*.mlmodelc/**", "README.md", "LICENSE*"])
    snapshot_download("openai/whisper-base", revision=TOKENIZER_REVISION,
                      local_dir=tokenizer, allow_patterns=["*.json", "merges.txt", "LICENSE*"])
    required = [model / f"{name}.mlmodelc" / "metadata.json"
                for name in ["AudioEncoder", "TextDecoder", "MelSpectrogram"]]
    if not all(path.is_file() for path in required):
        raise RuntimeError("Incomplete pinned Core ML model")
    repository = Path(__file__).resolve().parents[1]
    sources = json.loads((repository / "tools/RecitationEngineProbe/fixtures/sources.json").read_text())
    fixtures = root / "fixtures"
    fixtures.mkdir(exist_ok=True)
    chunks = {}
    rows = []
    for source in sources:
        path = fixtures / source["file"]
        if not path.exists():
            with urllib.request.urlopen(source["url"], timeout=60) as response:
                path.write_bytes(response.read())
        if hashlib.sha256(path.read_bytes()).hexdigest() != source["sha256"]:
            raise RuntimeError(f"Reference audio changed: {source['verse']}")
        pcm = subprocess.check_output(["ffmpeg", "-v", "error", "-i", str(path),
                                       "-f", "s16le", "-ac", "1", "-ar", "16000", "-"])
        chunks[source["verse"]] = pcm
        rows.append(dict(name=source["verse"], file=source["file"], kind="professional-reference"))

    def write(name, kind, pcm):
        filename = name + ".wav"
        with wave.open(str(fixtures / filename), "wb") as output:
            output.setnchannels(1); output.setsampwidth(2); output.setframerate(16000)
            output.writeframes(pcm)
        rows.append(dict(name=name, file=filename, kind=kind))

    pause = bytes(16000)  # exactly half a second of 16-bit mono silence
    for name, kind, keys in [
        ("assembled-repeat", "repeat", ["112:1", "112:1", "112:2", "112:3", "112:4"]),
        ("assembled-return", "return", ["114:1", "114:2", "114:1", "114:2", "114:3"])
    ]:
        write(name, kind, pause.join(chunks[key] for key in keys))
    write("silence", "silence", bytes(16000 * 2 * 8))
    rng = random.Random(20261008)
    noise = b"".join(rng.randint(-800, 800).to_bytes(2, "little", signed=True)
                     for _ in range(16000 * 8))
    write("noise", "noise", noise)
    (fixtures / "fixtures.json").write_text(json.dumps(rows, indent=2) + "\n")
    evidence = dict(model=MODEL, model_revision=MODEL_REVISION,
                    tokenizer="openai/whisper-base", tokenizer_revision=TOKENIZER_REVISION,
                    references=sources, generated_audio="Explicit test assemblies, not live microphone recordings",
                    files=[])
    for folder in [model, tokenizer, fixtures]:
        for path in sorted(folder.rglob("*")):
            if path.is_file() and ".cache" not in path.parts:
                evidence["files"].append(dict(path=str(path.relative_to(root)),
                    sha256=hashlib.sha256(path.read_bytes()).hexdigest(), bytes=path.stat().st_size))
    (root / "data-provenance.json").write_text(json.dumps(evidence, indent=2) + "\n")
    print("Prepared 14 explicitly identified engine fixtures and pinned local models.")


if __name__ == "__main__":
    main()
