"""Experimental acoustic-only classifier with disjoint participant splits.

No expected transcript, recognizer output, private recording or paid training.
Published binary labels cover one narrowly selected articulation category only.
"""
import concurrent.futures
import csv
import hashlib
import io
import json
from pathlib import Path
import re
import time
import urllib.request

import av
import numpy as np
import sklearn
from sklearn.linear_model import LogisticRegression
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler

REV = "973b5ef1d1532bcbe7e9a5a5b0dce125cc4d0dac"
BASE = f"https://huggingface.co/datasets/MuazAhmad7/Surah_Ikhlas-Labeled_Dataset/resolve/{REV}/"


def read(name):
    with urllib.request.urlopen(BASE + name, timeout=90) as response:
        data = response.read(10_000_001)
    if len(data) > 10_000_000:
        raise ValueError("Unexpected public fixture size")
    return data


metadata = read("metadata.csv")
rows = list(csv.DictReader(metadata.decode("utf-8-sig").splitlines()))
chosen = []
for row in rows:
    match = re.fullmatch(r"data/ID(\d+)V([12])([TF])\.wav", row["file_name"])
    if not match or (row["label_name"] == "error" and row["error_explanation"].strip() != "خطأ في قلقلة حرف الدال"):
        continue
    if int(row["verse_number"]) != int(match[2]) or (match[3] == "T") != (row["label_name"] == "correct"):
        raise ValueError("Published label/filename disagreement")
    participant = int(match[1])
    row = dict(row, participant=participant, split="train" if participant < 180 else "development" if participant < 250 else "test")
    chosen.append(row)


def features(signal):
    if len(signal) < 1600 or not np.isfinite(signal).all() or np.sqrt(np.mean(signal**2)) < 0.0001:
        return None
    signal = signal / max(0.001, float(np.max(np.abs(signal))))
    frames = np.lib.stride_tricks.sliding_window_view(signal, 400)[::160]
    energy = np.sqrt(np.mean(frames**2, axis=1))
    active = np.flatnonzero(energy > max(0.01, float(energy.max()) * 0.05))
    if not len(active):
        return None
    ending = min(len(signal), int(active[-1]) * 160 + 400)
    result = []
    for seconds in [0.05, 0.10, 0.20, 0.35, 0.50, 0.80]:
        tail = signal[max(0, ending-int(16000*seconds)):ending]
        result.extend([np.mean(tail**2), np.mean(np.diff(tail)**2), np.mean(tail[:-1]*tail[1:] < 0),
                       *np.quantile(np.abs(tail), [0.25, 0.5, 0.75, 0.95])])
        spectrum = np.abs(np.fft.rfft(tail * np.hanning(len(tail))))**2
        frequency = np.fft.rfftfreq(len(tail), 1/16000)
        total = max(1e-12, float(spectrum.sum()))
        result.append(float(np.sum(frequency*spectrum))/total/8000)
        for low, high in [(0, 500), (500, 1500), (1500, 3000), (3000, 8001)]:
            result.append(float(spectrum[(frequency >= low) & (frequency < high)].sum())/total)
    return np.asarray(result, dtype=np.float64)


def prepare(row):
    raw = read(row["file_name"])
    samples = []
    resampler = av.AudioResampler(format="fltp", layout="mono", rate=16000)
    with av.open(io.BytesIO(raw)) as container:
        for frame in container.decode(audio=0):
            samples.extend(f.to_ndarray().reshape(-1) for f in resampler.resample(frame))
        samples.extend(f.to_ndarray().reshape(-1) for f in resampler.resample(None))
    signal = np.concatenate(samples).astype(np.float32)
    started = time.monotonic()
    vector = features(signal)
    return dict(file=row["file_name"], participant=row["participant"], split=row["split"],
                label=int(row["label_name"] == "error"), sha256=hashlib.sha256(raw).hexdigest(),
                featureSeconds=time.monotonic()-started, vector=vector)


with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    samples = list(pool.map(prepare, chosen))
groups = {name: [s for s in samples if s["split"] == name and s["vector"] is not None]
          for name in ["train", "development", "test"]}
if any(len(group) < 30 or len({s["label"] for s in group}) != 2 for group in groups.values()):
    raise ValueError("Insufficient independently split category data")
X = {name: np.stack([s["vector"] for s in group]) for name, group in groups.items()}
y = {name: np.array([s["label"] for s in group]) for name, group in groups.items()}
best = None
for regularization in [0.01, 0.1, 1.0]:
    candidate = make_pipeline(StandardScaler(), LogisticRegression(C=regularization, class_weight="balanced", max_iter=2000, random_state=0))
    candidate.fit(X["train"], y["train"])
    predicted = candidate.predict(X["development"])
    tp = int(((predicted == 1) & (y["development"] == 1)).sum())
    fp = int(((predicted == 1) & (y["development"] == 0)).sum())
    fn = int(((predicted == 0) & (y["development"] == 1)).sum())
    score = 5*tp/(5*tp+4*fp+fn) if 5*tp+4*fp+fn else 0
    if best is None or score > best[0]:
        best = score, candidate, regularization
model = best[1]
predicted = model.predict(X["test"])
tp = int(((predicted == 1) & (y["test"] == 1)).sum())
fp = int(((predicted == 1) & (y["test"] == 0)).sum())
all_test = [s for s in samples if s["split"] == "test"]
positive_test = sum(s["label"] for s in all_test)
scaler, classifier = model.steps[0][1], model.steps[1][1]
report = dict(schema=1, policy="acoustic-tail-development-1", repository="MuazAhmad7/Surah_Ikhlas-Labeled_Dataset", revision=REV,
    license="CC-BY-4.0", attribution="MuazAhmad7, Surah Ikhlas Labeled Dataset",
    metadataSHA256=hashlib.sha256(metadata).hexdigest(), category="Reported dal-qalqla error in verses 112:1 and 112:2",
    split="train participant<180; development 180..249; previously unprobed test>=250",
    limitation="Published labels, no verified equivalence to original expert archive. Not general Tajweed support or a calibrated correctness probability.",
    samples={name: len(group) for name, group in groups.items()},
    measurements=dict(testSamples=len(all_test), assessed=len(groups["test"]), truePositives=tp, falsePositives=fp,
        precision=tp/(tp+fp) if tp+fp else None, recallIncludingAbstentions=tp/positive_test if positive_test else None,
        coverage=len(groups["test"])/len(all_test)),
    runtime=dict(numpy=np.__version__, sklearn=sklearn.__version__, av=av.__version__, device="CI CPU; not iPhone"),
    testPredictions=[dict(file=s["file"], label=s["label"], prediction=int(p)) for s, p in zip(groups["test"], predicted)],
    fittedModel=dict(C=best[2], mean=scaler.mean_.tolist(), scale=scaler.scale_.tolist(), coefficients=classifier.coef_[0].tolist(), intercept=float(classifier.intercept_[0])),
    sourceFiles=[{k: v for k, v in s.items() if k != "vector"} for s in samples])
Path("qalqala-acoustic-evaluation.json").write_text(json.dumps(report, ensure_ascii=False, indent=2)+"\n")
print(json.dumps(report["measurements"]), flush=True)
