"""Execute pinned, separately licensed phonetic inference on public fixtures.

This is a deployment probe, not learner-error accuracy or Tajweed certification.
No microphone recordings or expected Quran text are sent to this backend.
"""
import hashlib
import json
from pathlib import Path
import time
import urllib.request
import resource
import csv
import re
from collections import Counter

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
for name in ["001001.mp3", "001002.mp3", "001003.mp3", "112001.mp3", "112002.mp3", "112003.mp3", "112004.mp3", "114001.mp3", "114002.mp3", "114003.mp3"]:
    path = fixtures / name
    expected = next(s["sha256"] for s in sources if s["file"] == name)
    if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
        raise ValueError("Fixture digest mismatch")
    cases.append((name, decode_audio(path)))
base = np.concatenate([decode_audio(fixtures / "112001.mp3"), decode_audio(fixtures / "112002.mp3")])
# Same fixed source edit used by the independent text-ASR comparison. These
# manipulated public recordings are diagnostics, not expert-labelled learners.
first, last = 19200, 33920
report["editDefinition"] = dict(source=["112001.mp3", "112002.mp3"], cutFrames=[first, last], samplingRate=16000,
                                labels="Signal edits only; no expert learner-error ground truth")
cases.extend([
    ("composite-unaltered", base),
    ("composite-cut", np.concatenate([base[:first], base[last:]])),
    ("composite-repetition", np.concatenate([base[:last], base[first:last], base[last:]])),
    ("composite-hesitation", np.concatenate([base[:last], np.zeros(32000, dtype=np.float32), base[last:]])),
])
cases.append(("digital-silence-8s", np.zeros(128000, dtype=np.float32)))
DATA_REV = "973b5ef1d1532bcbe7e9a5a5b0dce125cc4d0dac"
DATA_BASE = f"https://huggingface.co/datasets/MuazAhmad7/Surah_Ikhlas-Labeled_Dataset/resolve/{DATA_REV}/"
metadata_file = WORK / "learner-labels.csv"
labels_hash = fetch(DATA_BASE + "metadata.csv", metadata_file)
rows = list(csv.DictReader(metadata_file.read_text(encoding="utf-8-sig").splitlines()))
if len(rows) != 1506 or Counter(r["label_name"] for r in rows) != {"error": 851, "correct": 655}:
    raise ValueError("Unexpected published learner-label schema")
selected_labels = {}
for verse in [1, 2]:
    for label in ["correct", "error"]:
        chosen = []
        for row in rows:
            match = re.fullmatch(r"data/ID(\d+)V([1-4])([TF])\.wav", row["file_name"])
            if not match or int(row["verse_number"]) != verse or row["label_name"] != label:
                continue
            # All samples from each participant stay in one fixed split.
            if int(match[1]) % 5 in [0, 1]:
                continue
            if label == "error" and row["error_explanation"].strip() != "خطأ في قلقلة حرف الدال":
                continue
            chosen.append(row)
            if len(chosen) == 12:
                break
        if len(chosen) != 12:
            raise ValueError("Insufficient prespecified held-out category examples")
        for row in chosen:
            name = Path(row["file_name"]).name
            path = WORK / name
            sha = fetch(DATA_BASE + row["file_name"], path)
            signal = decode_audio(path)
            if not 0 < len(signal) <= 16000 * 60:
                raise ValueError("Unexpected public recording duration")
            case = "learner-" + name
            cases.append((case, signal))
            selected_labels[case] = dict(label=label, verse=verse, sha256=sha,
                                         errorLocation=row["error_location"], explanation=row["error_explanation"])
report["learnerDataset"] = dict(repository="MuazAhmad7/Surah_Ikhlas-Labeled_Dataset", revision=DATA_REV,
    metadataSHA256=labels_hash, license="CC-BY-4.0", attribution="MuazAhmad7, Surah Ikhlas Labeled Dataset",
    lineage="Published labels; byte-equivalence to Mendeley expert archive not established",
    split="Held-out participant IDs modulo 5 in {2,3,4}; no fitting or threshold tuning",
    policy="development-qalqla-tail-1: last nonblank qalqla head class; require final dal identity; no calibrated probabilities",
    limitation="Only verse 1/2, correct versus single reported dal-qalqla error; not general Tajweed accuracy",
    samples=selected_labels)
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
            collapsed, previous, occurrences = [], None, []
            for frame, token in enumerate(ids):
                if token != previous and token != 0:
                    collapsed.append(token)
                    occurrences.append(dict(tokenID=token, startFrame=frame, endFrame=frame+1))
                elif token != 0 and occurrences:
                    occurrences[-1]["endFrame"] = frame + 1
                previous = token
            # Head mapping remains explicit; never guess categories from dimensions.
            entry["ctcTokenIDs"] = collapsed
            entry["ctcFrameOccurrences"] = occurrences
            key = node.name.removesuffix("_logits").removeprefix("logits_")
            mapping = vocabulary.get(key)
            if isinstance(mapping, dict) and all(isinstance(v, int) for v in mapping.values()):
                inverse = {v: k for k, v in mapping.items()}
                entry["decodedLabels"] = [inverse.get(i, f"unknown:{i}") for i in collapsed]
        heads.append(entry)
    measured = dict(name=name, audioSeconds=len(audio)/16000, wallSeconds=time.monotonic()-started, heads=heads)
    if name in selected_labels:
        phone = next(h for h in heads if h["output"] == "phonemes")["ctcTokenIDs"]
        qalqla = next(h for h in heads if h["output"] == "qalqla")["ctcTokenIDs"]
        tail_dal = 8 in phone[-3:]
        prediction = ("correct" if qalqla[-1] == 1 else "error") if tail_dal and qalqla and qalqla[-1] in [1, 2] else "unassessable"
        measured["publishedLabel"] = selected_labels[name]["label"]
        measured["developmentPrediction"] = prediction
    report["cases"].append(measured)
    learner = [c for c in report["cases"] if "publishedLabel" in c]
    if learner:
        tp = sum(c["publishedLabel"] == "error" and c["developmentPrediction"] == "error" for c in learner)
        fp = sum(c["publishedLabel"] == "correct" and c["developmentPrediction"] == "error" for c in learner)
        positives = sum(c["publishedLabel"] == "error" for c in learner)
        assessed = sum(c["developmentPrediction"] != "unassessable" for c in learner)
        report["categoryMeasurements"] = dict(samples=len(learner), assessed=assessed,
            precision=tp/(tp+fp) if tp+fp else None, recallIncludingAbstentions=tp/positives if positives else None,
            coverage=assessed/len(learner), truePositives=tp, falsePositives=fp,
            scope="Unfitted baseline versus published labels; not a production acceptance result")
    report["peakHostRSSKiB"] = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(f"Executed phonetic inference: {name}", flush=True)
