"""Convert a pinned CTC candidate, then separately execute actual Apple parity.

Only public fixtures. A converted package is not a working iOS integration or
pronunciation acceptance. Never synthesize expected words into decoded audio.
"""
import gc
import hashlib
import json
import os
from pathlib import Path
import platform
import resource
import sys
import time
import unicodedata
import urllib.request

import coremltools as ct
import numpy as np

ROOT=Path(__file__).resolve().parents[3]
OUT=ROOT/'release/ctc-coreml-candidate'
REV='b539d5fa66deb820c8e4762171ecb284ace4b52d'
REPO='rabah2026/wav2vec2-large-xlsr-53-arabic-quran'
SHA='202cb1eefd7c399d117140014dc773da358e895e6e6b2312d999e7fda503febf'


def digest(path):
    value=hashlib.sha256()
    with path.open('rb') as source:
        while chunk:=source.read(1024*1024):value.update(chunk)
    return value.hexdigest()


def decode(ids,vocab):
    inverse={value:key for key,value in vocab.items()}
    parts=[];last=None
    for token in ids:
        if token!=last and token!=0:parts.append(inverse.get(token,'<unknown>'))
        last=token
    return ''.join(parts).replace('|',' ').strip()


def lexical(text):
    return ' '.join(''.join(c for c in unicodedata.normalize('NFKD',text)
        if c.isalpha() or c.isspace()).replace('ـ','').split())


def convert():
    import av
    import torch
    from transformers import Wav2Vec2ForCTC,Wav2Vec2Processor
    OUT.mkdir(parents=True,exist_ok=True)
    work=ROOT/'.ctc-coreml-source';work.mkdir(exist_ok=True)
    receipt={}
    for name in ['config.json','preprocessor_config.json','tokenizer_config.json','special_tokens_map.json','vocab.json','README.md','model.safetensors']:
        path=work/name;length=0
        with urllib.request.urlopen(f'https://huggingface.co/{REPO}/resolve/{REV}/{name}',timeout=180) as source,path.open('wb') as target:
            while chunk:=source.read(1024*1024):
                length+=len(chunk)
                if length>(1262037080 if name=='model.safetensors' else 2_000_000):raise ValueError('Unexpected source length')
                target.write(chunk)
        receipt[name]=dict(bytes=length,sha256=digest(path))
    if receipt['model.safetensors']!={'bytes':1262037080,'sha256':SHA}:raise ValueError('Source weights integrity failed')
    vocab=json.loads((work/'vocab.json').read_text())
    config=json.loads((work/'config.json').read_text())
    processor=Wav2Vec2Processor.from_pretrained(str(work),local_files_only=True,trust_remote_code=False)
    torch.set_num_threads(2);torch.set_num_interop_threads(1)
    original=Wav2Vec2ForCTC.from_pretrained(str(work),local_files_only=True,trust_remote_code=False,attn_implementation='eager').eval()
    def audio(path):
        chunks=[];converter=av.AudioResampler(format='fltp',layout='mono',rate=16000)
        with av.open(str(path)) as container:
            for frame in container.decode(audio=0):chunks.extend(item.to_ndarray().reshape(-1) for item in converter.resample(frame))
            chunks.extend(item.to_ndarray().reshape(-1) for item in converter.resample(None))
        return np.concatenate(chunks).astype(np.float32)
    fixtures=ROOT/'ios/AtharTests/RecitationFixtures';cases=[];signals={}
    for row in json.loads((fixtures/'recitation-reference-sources.json').read_text()):
        path=fixtures/row['file']
        if digest(path)!=row['sha256']:raise ValueError('Public fixture integrity failed')
        signal=audio(path);signals[row['verse']]=signal;cases.append((row['file'],signal))
    base=np.concatenate([signals['112:1'],signals['112:2']]);a,b=19200,33920
    cases.extend([('public-composite',base),('public-cut',np.concatenate([base[:a],base[b:]])),
        ('public-repeat',np.concatenate([base[:b],base[a:b],base[b:]])),
        ('public-hesitation',np.concatenate([base[:b],np.zeros(32000,dtype=np.float32),base[b:]])),
        ('digital-silence',np.zeros(128000,dtype=np.float32))])
    cases.extend((key+'-first-2s',signals[key][:32000]) for key in ['112:1','114:1','1:2'])
    rows=[]
    for index,(name,signal) in enumerate(cases):
        inputs=processor(signal,sampling_rate=16000,return_tensors='pt',padding=False)
        with torch.inference_mode():logits=original(**inputs).logits[0].float().numpy()
        path=OUT/f'input-{index}.npy';np.save(path,inputs.input_values.numpy())
        ids=logits.argmax(axis=-1).tolist()
        rows.append(dict(name=name,input=path.name,samples=len(signal),frames=len(ids),rawSourceText=decode(ids,vocab),inputSHA256=digest(path)))
    class Wrapper(torch.nn.Module):
        def __init__(self,model):super().__init__();self.model=model
        def forward(self,input_values):return self.model(input_values=input_values,return_dict=False)[0]
    with torch.inference_mode():
        traced=torch.jit.trace(Wrapper(original).eval(),torch.tensor(np.load(OUT/'input-3.npy')),strict=False,check_trace=False)
    precision=os.environ.get('NOOR_CTC_PRECISION','float32')
    if precision not in {'float32','linear-half'}:raise ValueError('Unsupported arithmetic configuration')
    arithmetic=ct.precision.FLOAT32 if precision=='float32' else ct.transform.FP16ComputePrecision(
        op_selector=lambda op: op.op_type=='linear')
    model=ct.convert(traced,convert_to='mlprogram',minimum_deployment_target=ct.target.iOS17,
        inputs=[ct.TensorType(name='input_values',shape=(1,ct.RangeDim(lower_bound=1600,upper_bound=128000,default=32000)),dtype=np.float32)],
        # XLSR activations can overflow half precision despite finite weights.
        # Keep arithmetic in float32; weight storage compression is separate.
        outputs=[ct.TensorType(name='logits',dtype=np.float32)],compute_precision=arithmetic,skip_model_load=True)
    del original,traced;gc.collect()
    optimization=ct.optimize.coreml.OptimizationConfig(global_config=ct.optimize.coreml.OpLinearQuantizerConfig(
        mode='linear_symmetric',dtype=np.int8,weight_threshold=512))
    model=ct.optimize.coreml.linear_quantize_weights(model,config=optimization)
    model.save(str(OUT/'NoorCTC.mlpackage'))
    files=[dict(path=str(path.relative_to(OUT)),bytes=path.stat().st_size,sha256=digest(path)) for path in sorted((OUT/'NoorCTC.mlpackage').rglob('*')) if path.is_file()]
    (OUT/'vocab.json').write_bytes((work/'vocab.json').read_bytes())
    (OUT/'preprocessor_config.json').write_bytes((work/'preprocessor_config.json').read_bytes())
    (OUT/'UPSTREAM-README.md').write_bytes((work/'README.md').read_bytes())
    with urllib.request.urlopen('https://www.apache.org/licenses/LICENSE-2.0.txt',timeout=45) as response:(OUT/'APACHE-2.0.txt').write_bytes(response.read(100_000))
    manifest=dict(schema=1,sourceModel=REPO,sourceRevision=REV,sourceSHA256=SHA,sourceReceipt=receipt,
        coremltools=ct.__version__,torch=torch.__version__,minimumDeploymentTarget='iOS17',
        compression='Core ML linear symmetric int8 weights',arithmetic=precision,
        cases=rows,files=files,convKernel=config['conv_kernel'],convStride=config['conv_stride'],
        vocabularySHA256=receipt['vocab.json']['sha256'],preprocessorSHA256=receipt['preprocessor_config.json']['sha256'],
        converted=True,appleRuntimeVerified=False,iPhoneVerified=False,productionPromoted=False)
    (OUT/'conversion.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(dict(converted=True,packageBytes=sum(item['bytes'] for item in files),appleRuntimeVerified=False)),flush=True)


def verify():
    if platform.system()!='Darwin':raise RuntimeError('Apple Core ML must execute on actual macOS')
    manifest=json.loads((OUT/'conversion.json').read_text())
    if manifest['sourceRevision']!=REV or manifest['sourceSHA256']!=SHA:raise ValueError('Candidate identity mismatch')
    for item in manifest['files']:
        path=OUT/item['path']
        if not path.resolve().is_relative_to(OUT.resolve()):raise ValueError('Invalid package path')
        if path.stat().st_size!=item['bytes'] or digest(path)!=item['sha256']:raise ValueError('Converted model integrity failed')
    if digest(OUT/'vocab.json')!=manifest['vocabularySHA256']:raise ValueError('Vocabulary integrity failed')
    if digest(OUT/'preprocessor_config.json')!=manifest['preprocessorSHA256']:raise ValueError('Frontend integrity failed')
    vocab=json.loads((OUT/'vocab.json').read_text())
    model=ct.models.MLModel(str(OUT/'NoorCTC.mlpackage'),compute_units=ct.ComputeUnit.CPU_ONLY)
    results=[]
    for row in manifest['cases']:
        path=OUT/row['input']
        if digest(path)!=row['inputSHA256']:raise ValueError('Input identity changed')
        before=time.monotonic();logits=np.asarray(model.predict({'input_values':np.load(path)})['logits'])
        valid=logits.ndim==3 and logits.shape[0]==1 and logits.shape[1]==row['frames'] and logits.shape[2]==len(vocab) and bool(np.isfinite(logits).all())
        text=decode(logits[0].argmax(axis=-1).tolist(),vocab) if valid else ''
        same=valid and lexical(text)==lexical(row['rawSourceText'])
        if row['name']=='digital-silence':same=same and not text
        finite=np.isfinite(logits)
        results.append(dict(name=row['name'],seconds=time.monotonic()-before,shape=list(logits.shape),
            finiteValues=int(finite.sum()),totalValues=int(logits.size),
            finiteAbsoluteMaximum=float(np.abs(logits[finite]).max()) if finite.any() else None,
            rawAppleText=text,rawSourceText=row['rawSourceText'],rawUTF8Equal=text==row['rawSourceText'],lexicalParity=same))
        print(json.dumps(results[-1],ensure_ascii=False),flush=True)
    passed=bool(results) and all(row['lexicalParity'] for row in results)
    report=dict(schema=1,sourceRevision=REV,arithmetic=manifest.get('arithmetic','float32'),appleRuntimeExecuted=True,computeUnits='CPU_ONLY',lexicalParityPassed=passed,
        scope='Actual macOS Core ML on public fixtures; not iPhone microphone, learner-error accuracy, or Tajweed',
        coremltools=ct.__version__,cases=results,peakHostRSSBytes=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss,
        iPhoneVerified=False,productionPromoted=False)
    (ROOT/'ctc-apple-parity.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    if not passed:raise RuntimeError('Actual Apple lexical parity failed; do not promote candidate')


if __name__=='__main__':
    if sys.argv[1:] == ['convert']:convert()
    elif sys.argv[1:] == ['verify']:verify()
    else:raise SystemExit('Use convert on CPU, then verify on actual macOS')
