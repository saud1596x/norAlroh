"""Measure a frozen phonetic-feature classifier on disjoint public speakers.

The earlier last-head heuristic and raw-waveform classifier failed acceptance.
This experiment uses actual independently decoded phonetic heads. It never
receives expected Quran text, never uploads recordings, and cannot enable an
app capability merely because this evaluation script runs successfully.
"""
import concurrent.futures
import csv
import hashlib
import io
import json
from pathlib import Path
import re
import resource
import time
import urllib.request

import av
import numpy as np
import onnxruntime as ort
from sklearn.linear_model import LogisticRegression
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler
from transformers import SeamlessM4TFeatureExtractor

WORK = Path('.phonetic-category-evaluation')
WORK.mkdir(exist_ok=True)
REV = '5d5a3510728b3d02e4a84897c311a5d404505ee9'
UPSTREAM = '01a1ef9fbe40d144ef845101e89ff924aed3fef5'
MODEL_SHA = '3ef7f9760b54161d876b5866fccd19cbcc7b793386753f515395f2d5012e9f96'
DATA_REV = '973b5ef1d1532bcbe7e9a5a5b0dce125cc4d0dac'
DATA_BASE = f'https://huggingface.co/datasets/MuazAhmad7/Surah_Ikhlas-Labeled_Dataset/resolve/{DATA_REV}/'


def fetch(url, limit):
    with urllib.request.urlopen(url, timeout=180) as response:
        raw = response.read(limit + 1)
    if len(raw) > limit:
        raise ValueError('Public asset exceeds its declared limit')
    return raw


model = WORK / 'muaalem_tajweed_int8.onnx'
with urllib.request.urlopen(f'https://huggingface.co/Abddar/muaalem-v3-2-int8-android-onnx/resolve/{REV}/{model.name}', timeout=180) as response, model.open('wb') as target:
    sha = hashlib.sha256(); length = 0
    while chunk := response.read(1024 * 1024):
        length += len(chunk)
        if length > 876466434:
            raise ValueError('Unexpected model length')
        sha.update(chunk); target.write(chunk)
if length != 876466434 or sha.hexdigest() != MODEL_SHA:
    raise ValueError('Pinned phonetic model integrity failed')
metadata_hashes = {}
for name in ['config.json', 'preprocessor_config.json', 'vocab.json', 'README.md']:
    raw = fetch(f'https://huggingface.co/obadx/muaalem-model-v3_2/resolve/{UPSTREAM}/{name}', 2_000_000)
    (WORK / name).write_bytes(raw)
    metadata_hashes[name] = hashlib.sha256(raw).hexdigest()
vocab = json.loads((WORK / 'vocab.json').read_text())
if vocab.get('phonemes', {}).get('د') != 8:
    raise ValueError('Pinned phoneme identity changed')
extractor = SeamlessM4TFeatureExtractor.from_pretrained(str(WORK), local_files_only=True)
options = ort.SessionOptions(); options.intra_op_num_threads = 2; options.inter_op_num_threads = 1
options.enable_cpu_mem_arena = False; options.enable_mem_pattern = False
session = ort.InferenceSession(str(model), sess_options=options, providers=['CPUExecutionProvider'])
names = [node.name for node in session.get_outputs()]
labels = fetch(DATA_BASE + 'metadata.csv', 2_000_000)
rows = []
for row in csv.DictReader(labels.decode('utf-8-sig').splitlines()):
    match = re.fullmatch(r'data/ID(\d+)V([12])([TF])\.wav', row['file_name'])
    if not match or row['label_name'] == 'error' and row['error_explanation'].strip() != 'خطأ في قلقلة حرف الدال':
        continue
    if int(row['verse_number']) != int(match[2]) or (match[3] == 'T') != (row['label_name'] == 'correct'):
        raise ValueError('Published label identity mismatch')
    participant = int(match[1])
    rows.append(dict(row, participant=participant, split='train' if participant < 180 else 'development' if participant < 250 else 'test'))


def download(row):
    raw = fetch(DATA_BASE + row['file_name'], 10_000_000)
    target = WORK / Path(row['file_name']).name
    target.write_bytes(raw)
    return row, target, hashlib.sha256(raw).hexdigest()


def audio(path):
    chunks = []
    resampler = av.AudioResampler(format='fltp', layout='mono', rate=16000)
    with av.open(str(path)) as container:
        for frame in container.decode(audio=0):
            chunks.extend(item.to_ndarray().reshape(-1) for item in resampler.resample(frame))
        chunks.extend(item.to_ndarray().reshape(-1) for item in resampler.resample(None))
    return np.concatenate(chunks).astype(np.float32)


def softmax(logits):
    value = np.asarray(logits, dtype=np.float64)
    value -= value.max(axis=-1, keepdims=True)
    value = np.exp(value)
    return value / value.sum(axis=-1, keepdims=True)


def vector(signal):
    # Fixed predeclared signal/identity gates, independent of correctness labels.
    if not 1600 <= len(signal) <= 960_000 or not np.isfinite(signal).all() or np.sqrt(np.mean(signal**2)) < 0.0001:
        return None
    features = extractor(signal, sampling_rate=16000, return_tensors='np')
    inputs = {node.name: np.asarray(features[node.name], dtype=np.float32) for node in session.get_inputs()}
    output = dict(zip(names, session.run(None, inputs)))
    if not all(np.isfinite(value).all() for value in output.values()):
        return None
    phones = output['phonemes'][0].argmax(axis=-1)
    occurrences = []; previous = 0
    for frame, token in enumerate(phones.tolist()):
        if token and token != previous:
            occurrences.append((token, frame))
        previous = token
    # Native model vocabulary: dal=8. Require a decoded final-region dal;
    # absence is unassessable, never an automatically failed pronunciation.
    endings = [(token, frame) for token, frame in occurrences[-8:] if token == 8]
    if not endings:
        return None
    center = endings[-1][1]
    result = []
    for name in ['phonemes', 'qalqla', 'shidda_or_rakhawa', 'hams_or_jahr']:
        probabilities = softmax(output[name][0])
        for radius in [1, 3, 6]:
            region = probabilities[max(0, center-radius):min(len(probabilities), center+radius+1)]
            result.extend(region.mean(axis=0).tolist())
            result.extend(region.max(axis=0).tolist())
    return result


samples = []
# Fetch public licensed files concurrently; acoustic inference stays serialized
# to keep model memory bounded. No private microphone data is involved.
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    for row, path, digest in pool.map(download, rows):
        signal = audio(path)
        started = time.monotonic(); features = vector(signal)
        samples.append(dict(file=row['file_name'], participant=row['participant'], split=row['split'],
            label=int(row['label_name'] == 'error'), sha256=digest, seconds=len(signal)/16000,
            inferenceSeconds=time.monotonic()-started, vector=features))
        if len(samples) % 25 == 0:
            print(f'Actual phonetic inference completed {len(samples)}/{len(rows)} public samples', flush=True)
            Path('phonetic-qalqala-progress.json').write_text(json.dumps(dict(
                status='incomplete', completed=len(samples), planned=len(rows), modelSHA256=MODEL_SHA,
                acceptanceEstablished=False, promotedToProduction=False))+'\n')

groups = {key: [item for item in samples if item['split'] == key] for key in ['train', 'development', 'test']}
participants = {key: {item['participant'] for item in group} for key, group in groups.items()}
assert not (participants['train'] & participants['development'] or participants['train'] & participants['test'] or participants['development'] & participants['test'])
train = [item for item in groups['train'] if item['vector'] is not None]
development = [item for item in groups['development'] if item['vector'] is not None]
classifier = make_pipeline(StandardScaler(), LogisticRegression(C=0.1, max_iter=2000, random_state=20261015))
classifier.fit([item['vector'] for item in train], [item['label'] for item in train])
thresholds = [i/100 for i in range(5, 100)]


def measurement(items, threshold):
    valid = [item for item in items if item['vector'] is not None]
    probabilities = classifier.predict_proba([item['vector'] for item in valid])[:, 1] if valid else []
    predicted = [(item, float(score), bool(score >= threshold)) for item, score in zip(valid, probabilities)]
    tp = sum(item['label'] and error for item, _, error in predicted)
    fp = sum(not item['label'] and error for item, _, error in predicted)
    positives = sum(item['label'] for item in items)
    precision = tp / (tp+fp) if tp+fp else 0
    recall = tp / positives if positives else 0
    coverage = len(valid) / len(items) if items else 0
    return dict(total=len(items), assessed=len(valid), truePositive=tp, falsePositive=fp,
        precision=precision, recallIncludingAbstentions=recall, assessability=coverage,
        acceptanceTargetsMet=precision >= .97 and recall >= .90 and coverage >= .90), predicted


# Select only on development data; never retune after inspecting test scores.
def objective(threshold):
    measured, _ = measurement(groups['development'], threshold)
    p, r = measured['precision'], measured['recallIncludingAbstentions']
    return (.97 <= p and .90 <= r, 1.25*p*r/(.25*p+r) if p+r else 0, threshold)
threshold = max(thresholds, key=objective)
test, predictions = measurement(groups['test'], threshold)
report = dict(schema=1, policy='phonetic-final-dal-logistic-1', modelRevision=REV, modelSHA256=MODEL_SHA,
    upstreamRevision=UPSTREAM, modelLicense='MIT', metadataSHA256=metadata_hashes,
    datasetRevision=DATA_REV, metadataSHA256Dataset=hashlib.sha256(labels).hexdigest(), datasetLicense='CC-BY-4.0',
    datasetAttribution='MuazAhmad7, Surah Ikhlas Labeled Dataset',
    expertArchiveEquivalenceVerified=False, category='Published correct versus single dal-qalqala error in Ikhlas verses 1 and 2 only',
    scope='CPU acoustic investigation; no expected transcript, no iOS deployment, no product capability enabled',
    splits={key: len(value) for key, value in groups.items()}, selectedThreshold=threshold,
    development=measurement(groups['development'], threshold)[0], heldOutTest=test,
    peakHostRSSKiB=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss,
    classifierC=.1, scoresAreCalibratedProbabilities=False, promotedToProduction=False,
    samples=[{key: value for key, value in item.items() if key != 'vector'} for item in samples],
    heldOutPredictions=[dict(file=item['file'], rawClassifierScore=score, predictedError=error) for item, score, error in predictions])
Path('phonetic-qalqala-evaluation.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
print(json.dumps(dict(heldOutTest=test, selectedThreshold=threshold, promotedToProduction=False), ensure_ascii=False), flush=True)
