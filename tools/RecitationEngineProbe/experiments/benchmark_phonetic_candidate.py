"""Run a pinned unconstrained phonetic CTC model on public audio, locally.

This measures CPU inference, not mobile performance or Tajweed correctness.
No reference-text prompt, private recording, remote inference, pickle weights,
or fabricated accuracy. A separate annotated learner set is still required.
"""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import sys
import time

parser = argparse.ArgumentParser()
parser.add_argument('--runtime', type=Path, required=True)
parser.add_argument('--model', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
sys.path.insert(0, str(args.runtime.resolve()))
os.environ['HF_HUB_OFFLINE'] = '1'
os.environ['TRANSFORMERS_OFFLINE'] = '1'
import numpy as np
import scipy.signal
import soundfile as sf
import torch
from transformers import Wav2Vec2ForCTC, Wav2Vec2Processor

receipt = json.loads((args.model / 'download-receipt.json').read_text())
assert receipt['revision'] == '65c3ab93446f2f1041a18082433a911e5e154a9d'
for name, entry in receipt['files'].items():
    assert hashlib.sha256((args.model / name).read_bytes()).hexdigest() == entry['sha256']
torch.set_num_threads(2)
torch.set_num_interop_threads(1)
load_start = time.perf_counter()
processor = Wav2Vec2Processor.from_pretrained(str(args.model), local_files_only=True)
model = Wav2Vec2ForCTC.from_pretrained(str(args.model), local_files_only=True, trust_remote_code=False).eval()
report = {'repository': receipt['repository'], 'revision': receipt['revision'],
          'device': 'Windows CPU', 'torch': torch.__version__, 'threads': 2,
          'loadSeconds': time.perf_counter() - load_start, 'cases': [],
          'phonemeErrorRate': None, 'tajweedPrecision': None, 'tajweedRecall': None,
          'limits': ['No adjudicated phoneme/Tajweed references for these fixtures',
                     'Not integrated into iOS; no mobile latency or memory validation',
                     'Edited audio is not representative human mispronunciation']}
root = Path(__file__).resolve().parents[3]
fixtures = root / 'ios/AtharTests/RecitationFixtures'
samples = {}
for file in sorted(fixtures.glob('*.mp3')):
    waveform, rate = sf.read(file, dtype='float32', always_2d=True)
    waveform = waveform.mean(axis=1)
    if rate != 16_000:
        divisor = math.gcd(rate, 16_000)
        waveform = scipy.signal.resample_poly(waveform, 16_000 // divisor, rate // divisor).astype(np.float32)
    samples[file.stem] = waveform
cases = [(name, audio, 'public reference') for name, audio in samples.items()]
cases.append(('digital-silence', np.zeros(32_000, dtype=np.float32), 'silence control'))
if '112001' in samples:
    audio = samples['112001']
    cases.append(('quiet-112001', audio * .03, 'amplitude derivative'))
    rng = np.random.default_rng(17102026)
    cases.append(('noise-112001', (audio + rng.normal(0, .005, audio.shape)).astype(np.float32), 'seeded noise derivative'))
for name, audio, kind in cases:
    inputs = processor(audio, sampling_rate=16_000, return_tensors='pt')
    started = time.perf_counter()
    with torch.inference_mode():
        logits = model(**inputs).logits
        ids = logits.argmax(dim=-1)
    elapsed = time.perf_counter() - started
    raw = processor.batch_decode(ids)[0]
    report['cases'].append({'name': name, 'kind': kind,
        'audioSHA256': hashlib.sha256(audio.tobytes()).hexdigest(),
        'audioSeconds': len(audio) / 16_000, 'inferenceSeconds': elapsed,
        'rawPhoneticHypothesis': raw, 'logitShape': list(logits.shape),
        'finiteLogits': bool(torch.isfinite(logits).all()), 'confirmedTajweedErrors': 0})
    print(name, round(elapsed, 3), raw, flush=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
