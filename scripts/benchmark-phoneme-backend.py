"""Execute pinned, separately licensed phonetic inference on public fixtures.

This is a deployment probe, not learner-error accuracy or Tajweed certification.
No microphone recordings or expected Quran text are sent to this backend.
"""
import hashlib
import json
from pathlib import Path
import time
import urllib.request

import av
import numpy as np
import onnxruntime as ort
from transformers import SeamlessM4TFeatureExtractor

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / ".phoneme-probe"
WORK.mkdir(exist_ok=True)
REV = "5d5a3510728b3d02e4a84897c311a5d404505ee9"
UPSTREAM = "01a1ef9fbe40d144ef845101e89ff924aed3fef5"
SHA = "3ef7f9760b54161d876b5866fccd19cbcc7b793386753f515395f2d5012e9f96"


def fetch(url, destination, digest=None):
    with urllib.request.urlopen(url, timeout=180) as response, destination.open("wb") as output:
        state = hashlib.sha256()
        while chunk := response.read(1024 * 1024):
            state.update(chunk)
            output.write(chunk)
    if digest and state.hexdigest() != digest:
        raise ValueError("Model digest mismatch")
    return state.hexdigest()


model = WORK / "muaalem_tajweed_int8.onnx"
fetch(f"https://huggingface.co/Abddar/muaalem-v3-2-int8-android-onnx/resolve/{REV}/{model.name}", model, SHA)
if model.stat().st_size != 876466434:
    raise ValueError("Model length mismatch")
metadata = {}
for name in ["config.json", "preprocessor_config.json", "vocab.json", "README.md"]:
    metadata[name] = fetch(f"https://huggingface.co/obadx/muaalem-model-v3_2/resolve/{UPSTREAM}/{name}", WORK / name)
extractor = SeamlessM4TFeatureExtractor.from_pretrained(str(WORK), local_files_only=True)
options = ort.SessionOptions()
options.intra_op_num_threads = 2
options.inter_op_num_threads = 1
options.enable_cpu_mem_arena = False
options.enable_mem_pattern = False
session = ort.InferenceSession(str(model), sess_options=options, providers=["CPUExecutionProvider"])
vocabulary = json.loads((WORK / "vocab.json").read_text())
config = json.loads((WORK / "config.json").read_text())
report = dict(schema=1, model="Abddar/muaalem-v3-2-int8-android-onnx", revision=REV,
              sha256=SHA, upstreamRevision=UPSTREAM, license="MIT", metadataSHA256=metadata,
              provider=session.get_providers(), inputs=[dict(name=i.name, shape=i.shape, type=i.type) for i in session.get_inputs()],
              outputs=[dict(name=o.name, shape=o.shape) for o in session.get_outputs()],
              scope="Uncalibrated phonetic deployment probe; no learner-error accuracy claim", cases=[])
output = ROOT / "phoneme-probe-result.json"
output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
fixtures = ROOT / "ios/AtharTests/RecitationFixtures"
sources = json.loads((ROOT / "tools/RecitationEngineProbe/fixtures/sources.json").read_text())


def decode_audio(path):
    resampler = av.AudioResampler(format="fltp", layout="mono", rate=16000)
    frames = []
    with av.open(str(path)) as container:
        for frame in container.decode(audio=0):
            frames.extend(f.to_ndarray().reshape(-1) for f in resampler.resample(frame))
        frames.extend(f.to_ndarray().reshape(-1) for f in resampler.resample(None))
    return np.concatenate(frames).astype(np.float32)


cases = []
for name in ["112001.mp3", "112002.mp3", "114001.mp3"]:
    path = fixtures / name
    expected = next(s["sha256"] for s in sources if s["file"] == name)
    if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
        raise ValueError("Fixture digest mismatch")
    cases.append((name, decode_audio(path)))
cases.append(("digital-silence-8s", np.zeros(128000, dtype=np.float32)))
for name, audio in cases:
    started = time.monotonic()
    features = extractor(audio, sampling_rate=16000, return_tensors="np")
    inputs = {}
    for node in session.get_inputs():
        if node.name not in features:
            raise ValueError(f"Unknown model input: {node.name}; available: {list(features)}")
        dtype = np.int64 if node.type == "tensor(int64)" else np.float32
        inputs[node.name] = np.asarray(features[node.name], dtype=dtype)
    predictions = session.run(None, inputs)
    heads = []
    for node, values in zip(session.get_outputs(), predictions):
        values = np.asarray(values)
        entry = dict(output=node.name, shape=list(values.shape), finite=bool(np.isfinite(values).all()))
        if values.ndim == 3:
            ids = values.argmax(axis=-1)[0].tolist()
            collapsed, previous = [], None
            for token in ids:
                if token != previous and token != 0:
                    collapsed.append(token)
                previous = token
            # Head mapping remains explicit; never guess categories from dimensions.
            entry["ctcTokenIDs"] = collapsed
            key = node.name.removesuffix("_logits").removeprefix("logits_")
            mapping = vocabulary.get(key)
            if isinstance(mapping, dict) and all(isinstance(v, int) for v in mapping.values()):
                inverse = {v: k for k, v in mapping.items()}
                entry["decodedLabels"] = [inverse.get(i, f"unknown:{i}") for i in collapsed]
        heads.append(entry)
    report["cases"].append(dict(name=name, audioSeconds=len(audio)/16000,
                                wallSeconds=time.monotonic()-started, heads=heads))
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(f"Executed phonetic inference: {name}", flush=True)
