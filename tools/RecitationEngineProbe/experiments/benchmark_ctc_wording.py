"""Actual non-autoregressive Quran ASR comparison on pinned public audio.

No prompt, expected-text decoding, private recordings, training, mobile runtime
claim, or pronunciation verdict. Preserve raw CTC observations for inspection.
"""
import hashlib
import json
from pathlib import Path
import resource
import time
import urllib.request

import av
import numpy as np
import torch
from transformers import Wav2Vec2ForCTC, Wav2Vec2Processor

ROOT = Path(__file__).resolve().parents[3]
WORK = ROOT / '.ctc-wording-candidate'
WORK.mkdir(exist_ok=True)
REV = 'b539d5fa66deb820c8e4762171ecb284ace4b52d'
REPO = 'rabah2026/wav2vec2-large-xlsr-53-arabic-quran'
WEIGHT_SHA = '202cb1eefd7c399d117140014dc773da358e895e6e6b2312d999e7fda503febf'
BASE = f'https://huggingface.co/{REPO}/resolve/{REV}/'
receipt = {}


def download(name, size_limit, expected=None):
    target = WORK / name
    digest = hashlib.sha256(); length = 0
    with urllib.request.urlopen(BASE + name, timeout=180) as response, target.open('wb') as output:
        while chunk := response.read(1024 * 1024):
            length += len(chunk)
            if length > size_limit:
                raise ValueError('Unexpected model resource length')
            digest.update(chunk); output.write(chunk)
    if expected and digest.hexdigest() != expected:
        raise ValueError('Pinned model integrity failed')
    receipt[name] = dict(bytes=length, sha256=digest.hexdigest())


for name in ['config.json', 'preprocessor_config.json', 'tokenizer_config.json', 'special_tokens_map.json', 'vocab.json', 'README.md']:
    download(name, 2_000_000)
download('model.safetensors', 1262037080, WEIGHT_SHA)
if receipt['model.safetensors']['bytes'] != 1262037080:
    raise ValueError('Truncated model resource')
config = json.loads((WORK / 'config.json').read_text())
vocabulary = json.loads((WORK / 'vocab.json').read_text())
inverse = {value: key for key, value in vocabulary.items()}
if config.get('model_type') != 'wav2vec2' or vocabulary.get('<pad>') != 0 or vocabulary.get('|') != 4:
    raise ValueError('Unexpected CTC architecture or token identity')
torch.set_num_threads(2); torch.set_num_interop_threads(1)
processor = Wav2Vec2Processor.from_pretrained(str(WORK), local_files_only=True, trust_remote_code=False)
model = Wav2Vec2ForCTC.from_pretrained(str(WORK), local_files_only=True, trust_remote_code=False).eval()
engine = next((name for name in ['x86', 'fbgemm'] if name in torch.backends.quantized.supported_engines), None)
if engine is None:
    raise ValueError('No supported CPU int8 backend')
torch.backends.quantized.engine = engine
model = torch.ao.quantization.quantize_dynamic(model, {torch.nn.Linear}, dtype=torch.qint8, inplace=True)
stride = 1; receptive = 1
for kernel, step in zip(config['conv_kernel'], config['conv_stride']):
    receptive += (kernel - 1) * stride; stride *= step


def audio(path):
    parts=[]
    converter=av.AudioResampler(format='fltp', layout='mono', rate=16000)
    with av.open(str(path)) as container:
        for frame in container.decode(audio=0):
            parts.extend(f.to_ndarray().reshape(-1) for f in converter.resample(frame))
        parts.extend(f.to_ndarray().reshape(-1) for f in converter.resample(None))
    return np.concatenate(parts).astype(np.float32)


fixtures = ROOT / 'ios/AtharTests/RecitationFixtures'
sources = json.loads((fixtures / 'recitation-reference-sources.json').read_text())
cases=[]; signals={}
for row in sources:
    path=fixtures / row['file']
    if hashlib.sha256(path.read_bytes()).hexdigest() != row['sha256']:
        raise ValueError('Public audio fixture integrity failed')
    signal=audio(path); signals[row['verse']]=signal
    cases.append((row['file'], signal))
base=np.concatenate([signals['112:1'], signals['112:2']])
first,last=19200,33920
cases.extend([
    ('public-composite',base),
    ('public-cut',np.concatenate([base[:first],base[last:]])),
    ('public-repeat',np.concatenate([base[:last],base[first:last],base[last:]])),
    ('public-hesitation',np.concatenate([base[:last],np.zeros(32000,dtype=np.float32),base[last:]])),
    ('digital-silence-8s',np.zeros(128000,dtype=np.float32)),
])
report=dict(schema=1,model=REPO,revision=REV,declaredModelLicense='Apache-2.0',
    sourceReceipt=receipt,torchRuntime=torch.__version__,quantization='Actual dynamic int8 Linear layers on CPU; not Core ML',
    frontendStrideSamples=stride,frontendReceptiveFieldSamples=receptive,
    timingScope='CTC character-frame receptive fields; not independently reviewed word boundaries',
    evaluatedOnPrivateRecordings=False,trained=False,promotedToProduction=False,
    learnerErrorAccuracyEstablished=False,tajweedAssessed=False,cases=[])
for name,signal in cases:
    started=time.monotonic()
    inputs=processor(signal,sampling_rate=16000,return_tensors='pt',padding=False)
    with torch.inference_mode(): logits=model(**inputs).logits[0].float().cpu().numpy()
    if not np.isfinite(logits).all():raise ValueError('Invalid acoustic output')
    ids=logits.argmax(axis=-1).tolist()
    occurrences=[]; previous=None
    for frame,token in enumerate(ids):
        if token != 0 and token != previous:
            occurrences.append(dict(tokenID=token,label=inverse.get(token,'<unknown>'),startFrame=frame,endFrame=frame+1))
        elif token != 0 and occurrences:
            occurrences[-1]['endFrame']=frame+1
        previous=token
    text=processor.decode(ids)
    measured=dict(name=name,audioSeconds=len(signal)/16000,inferenceSeconds=time.monotonic()-started,
        outputFrames=len(ids),rawText=text,ctcOccurrences=occurrences,
        rms=float(np.sqrt(np.mean(signal**2))),digitalSilence=not bool(np.any(signal)))
    report['cases'].append(measured)
    report['peakHostRSSKiB']=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    (ROOT/'ctc-wording-candidate.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({key:value for key,value in measured.items() if key!='ctcOccurrences'},ensure_ascii=False),flush=True)
