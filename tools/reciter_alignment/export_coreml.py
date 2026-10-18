"""Bounded Mac-only independent CTC conversion and actual public-PCM parity.

No expected passage or forced alignment enters either recognizer. A successful
conversion does not establish learner accuracy, iPhone performance or release
approval. The original source and selected converted variant are compared on the
same actual samples before any package can be considered for app integration.
"""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import struct
import subprocess
import tempfile
import time
import urllib.request

import numpy as np
from quran_ctc import FILES, REVISION, verify_assets, QuranAligner

FIXTURES = {
    '001002': 'de9afb563958e2cb5352a2857512a35abd86b7c2c6ee22b3a5a7cee9af7882db',
    '002001': '48077d6641b2403e04c15585b0ede3b8eb3a3c354ae4d8d6f6a4882dc8106ebb',
}


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(chunk)
    return value.hexdigest()


def download(url, path, expected, limit):
    if path.is_file() and not path.is_symlink() and digest(path) == expected:
        return
    if path.is_symlink():
        raise ValueError('Refusing linked model/fixture destination')
    path.parent.mkdir(parents=True, exist_ok=True)
    pending = path.with_suffix(path.suffix + '.pending')
    received = 0
    try:
        with urllib.request.urlopen(url, timeout=60) as response, pending.open('wb') as stream:
            for block in iter(lambda: response.read(1024 * 1024), b''):
                received += len(block)
                if received > limit:
                    raise ValueError('Pinned public asset exceeds explicit size limit')
                stream.write(block)
        if digest(pending) != expected:
            raise ValueError('Pinned public bytes differ')
        pending.replace(path)
    finally:
        pending.unlink(missing_ok=True)


def load_pcm(path):
    # Apple's system decoder avoids compiling a separate FFmpeg binding on the
    # Mac runner. Both models receive this same actual decoded PCM, no padding.
    with tempfile.TemporaryDirectory(prefix='noor-public-pcm-') as temporary:
        wave = Path(temporary)/'actual.wav'
        subprocess.run(['/usr/bin/afconvert', '-f', 'WAVE', '-d', 'LEF32@16000',
                        '-c', '1', str(path), str(wave)], check=True, timeout=20)
        values = read_float_wave(wave.read_bytes())
    if not 400 <= len(values) <= 256000 or not np.isfinite(values).all():
        raise ValueError('Actual public clip outside bounded 16second conversion scope')
    return values


def read_float_wave(data):
    if len(data)>2_000_000 or data[:4]!=b'RIFF' or data[8:12]!=b'WAVE':
        raise ValueError('Expected bounded actual float WAVE')
    offset, fmt, pcm = 12, None, None
    while offset+8 <= len(data):
        name = data[offset:offset+4]
        size = struct.unpack_from('<I',data,offset+4)[0]
        first, end = offset+8, offset+8+size
        if end>len(data):raise ValueError('Truncated actual WAVE')
        if name==b'fmt ':fmt=data[first:end]
        if name==b'data':
            if pcm is not None:raise ValueError('Duplicate actual PCM chunk')
            pcm=data[first:end]
        offset=end+(size%2)
    if fmt is None or len(fmt)<16 or pcm is None:
        raise ValueError('Missing actual WAVE format/data')
    code,channels,rate,byte_rate,align,bits=struct.unpack_from('<HHIIHH',fmt)
    if code==0xfffe:
        if len(fmt)<40 or fmt[24:40]!=bytes.fromhex('0300000000001000800000aa00389b71'):
            raise ValueError('Unsupported actual WAVE subtype')
        code=3
    if (code,channels,rate,byte_rate,align,bits)!=(3,1,16000,64000,4,32) or len(pcm)%4:
        raise ValueError('Actual PCM decoder format differs')
    return np.frombuffer(pcm,dtype='<f4').copy()


def project(logits, source_vocab, vocab):
    values = logits - logits.max(axis=-1, keepdims=True)
    values = np.exp(values)
    values /= values.sum(axis=-1, keepdims=True)
    projected = np.zeros((len(values), len(vocab)), dtype=np.float32)
    normalizer = object.__new__(QuranAligner).normalizer
    for char, index in source_vocab.items():
        target = vocab['|'] if char == '|' else vocab.get(normalizer(char), 0) if len(char) == 1 else 0
        projected[:, target] += values[:, index]
    return projected


def greedy(values, vocab):
    reverse = {value: key for key, value in vocab.items()}
    labels = values.argmax(axis=-1)
    emitted = [int(v) for i, v in enumerate(labels) if v != 0 and (i == 0 or v != labels[i-1])]
    return ''.join(' ' if v == vocab['|'] else reverse[v] for v in emitted).split()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--model', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--precision', choices=('float16','float32'), default='float16')
    parser.add_argument('--prepare-only', action='store_true', help='Generate for a separate byte-pinned build step; not a parity pass')
    args = parser.parse_args()
    if platform.system() != 'Darwin':
        raise ValueError('Actual Core ML prediction is required; conversion-only output is insufficient')
    args.output.mkdir(parents=True, exist_ok=True)
    receipt_path = args.output / 'actual-conversion.json'
    if receipt_path.exists():
        raise ValueError('Do not overwrite a previous conversion/evaluation receipt')
    report = {'scope': 'INDEPENDENT_CTC_COREML_CONVERSION_NOT_LEARNER_ACCEPTANCE',
              'sourceRevision': REVISION, 'sourceFiles': FILES, 'productionApproved': False,
              'audioDecoder': 'Apple afconvert LEF32@16000 mono; no synthesized/padded samples',
              'phoneIntegrated': False, 'expectedTextPrompt': False, 'forcedAlignment': False,
              'precision': args.precision,
              'cases': [], 'status': 'STARTED'}
    def save():
        receipt_path.write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    save()
    for name, pin in FILES.items():
        download(f'https://huggingface.co/rabah2026/wav2vec2-large-xlsr-53-arabic-quran/resolve/{REVISION}/{name}',
                 args.model/name, pin, 1_300_000_000)
    verify_assets(args.model)
    print('NOOR_CTC_COREML_PINNED_SOURCE_READY', flush=True)
    import torch
    import coremltools as ct
    from transformers import Wav2Vec2ForCTC
    torch.set_num_threads(4)
    model = Wav2Vec2ForCTC.from_pretrained(str(args.model), local_files_only=True,
        use_safetensors=True, attn_implementation='eager').eval()
    # Freeze the already-evaluated positional-convolution weight. This removes
    # a training reparameterization, not the convolution or its learned values.
    for module in model.modules():
        if torch.nn.utils.parametrize.is_parametrized(module, 'weight'):
            torch.nn.utils.parametrize.remove_parametrizations(module, 'weight', leave_parametrized=True)
    class Logits(torch.nn.Module):
        def __init__(self):
            super().__init__()
            self.acoustic_model = model
        def forward(self, input_values):
            return self.acoustic_model(input_values).logits
    wrapper = Logits().eval()
    # Trace-only arbitrary values are not counted as acoustic acceptance.
    example = torch.from_numpy(np.random.default_rng(42).normal(0, .02, (1, 32000)).astype(np.float32))
    started = time.monotonic()
    with torch.inference_mode():
        traced = torch.jit.trace(wrapper, example, check_trace=False)
    report.update(torchVersion=torch.__version__, coremltoolsVersion=ct.__version__)
    print('NOOR_CTC_COREML_TRACE_READY', flush=True)
    converted = ct.convert(traced, source='pytorch', convert_to='mlprogram',
        inputs=[ct.TensorType(name='input_values', shape=(1, ct.RangeDim(400, 256000, default=32000)), dtype=np.float32)],
        outputs=[ct.TensorType(name='logits', dtype=np.float32)],
        compute_precision=ct.precision.FLOAT16 if args.precision=='float16' else ct.precision.FLOAT32,
        minimum_deployment_target=ct.target.iOS17,
        compute_units=ct.ComputeUnit.CPU_AND_GPU)
    float_path = args.output/f'quran-ctc-{args.precision}.mlpackage'
    converted.save(str(float_path))
    print('NOOR_CTC_COREML_FLOAT16_PACKAGE_READY', flush=True)
    if args.prepare_only:
        print('NOOR_CTC_SOURCE_GENERATED_NOT_ACOUSTICALLY_TESTED',flush=True)
        return
    source_vocab = json.loads((args.model/'vocab.json').read_text())
    normalizer = object.__new__(QuranAligner).normalizer
    letters = sorted({normalizer(c) for c in source_vocab if len(c) == 1 and normalizer(c) and c != '|'})
    vocab = {'<pad>': 0, '|': 1, **{c:i+2 for i,c in enumerate(letters)}}
    root = Path(__file__).resolve().parents[2]
    sources = json.loads((root/'tools/RecitationEngineProbe/fixtures/sources.json').read_text())
    sources += [{'file':'002001.mp3','sha256':FIXTURES['002001'],
                 'url':'https://everyayah.com/data/Abdul_Basit_Murattal_64kbps/002001.mp3'}]
    cases = []
    for source in sources:
        name, pin = source['file'], source['sha256']
        if not name[:6].isdigit() or name[6:]!='.mp3' or source['url']!=f'https://everyayah.com/data/Abdul_Basit_Murattal_64kbps/{name}':
            raise ValueError('Unexpected public conversion fixture')
        clip = args.output/'public-fixtures'/name
        download(source['url'],clip,pin,2_000_000)
        original = load_pcm(clip)
        cases.extend((name,pin,len(original),original*np.float32(gain),'public-gain='+str(gain)) for gain in (1.,.03))
        if name in {'001002.mp3','002001.mp3'}:
            cases.append((name,pin,len(original),original[:32000],'public-first-two-seconds'))
    cases += [('silence',None,16000,np.zeros(16000,dtype=np.float32),'generated-negative-control'),
              ('noise',None,16000,np.random.default_rng(14).normal(0,.001,16000).astype(np.float32),'generated-negative-control')]
    for name,pin,original_frames,pcm,kind in cases:
            length=len(pcm)
            conditioned = ((pcm-pcm.mean())/np.sqrt(pcm.var()+1e-7)).astype(np.float32)[None]
            with torch.inference_mode():
                expected = wrapper(torch.from_numpy(conditioned)).numpy()[0]
                traced_result = traced(torch.from_numpy(conditioned)).numpy()[0]
            expected = project(expected, source_vocab, vocab)
            if not np.allclose(expected, project(traced_result,source_vocab,vocab), atol=1e-5):
                raise ValueError('Traced source changed actual variable-length acoustic output')
            for variant, candidate in [(args.precision, converted)]:
                before = time.monotonic()
                actual = candidate.predict({'input_values': conditioned})['logits'][0]
                elapsed = time.monotonic()-before
                if actual.shape[0] != (length-400)//320+1 or not np.isfinite(actual).all():
                    raise ValueError('Converted output differs from actual frame clock')
                actual = project(actual, source_vocab, vocab)
                report['cases'].append({'sourceFile':name,'sourceSHA256':pin,'caseKind':kind,
                    'originalFrames':original_frames,'decodedFrames':length,'variant':variant,
                    'sourceRawWords':greedy(expected,vocab),'convertedRawWords':greedy(actual,vocab),
                    'sameRawWords':greedy(expected,vocab)==greedy(actual,vocab),
                    'frameLabelAgreement':float(np.mean(expected.argmax(-1)==actual.argmax(-1))),
                    'maxPosteriorDifference':float(np.max(np.abs(expected-actual))),
                    'predictionSeconds':elapsed})
                save()
                print('NOOR_CTC_COREML_ACTUAL_CASE',json.dumps(report['cases'][-1],ensure_ascii=False),flush=True)
    report.update(status='ACTUAL_PARITY_FINISHED',seconds=time.monotonic()-started,
                  allRawWordsEqual=all(case['sameRawWords'] for case in report['cases']))
    report['packages'] = [{ 'variant':variant,'files':[
        {'path':p.relative_to(folder).as_posix(),'sha256':digest(p),'bytes':p.stat().st_size}
        for p in sorted(folder.rglob('*')) if p.is_file()]}
        for variant,folder in [(args.precision,float_path)]]
    save()
    print('NOOR_CTC_COREML_RESULT',json.dumps(report,ensure_ascii=False),flush=True)
    if not report['allRawWordsEqual']:
        raise ValueError('Actual raw words changed after conversion/compression; do not promote')
    if any(case['convertedRawWords'] or case['sourceRawWords'] for case in report['cases']
           if case['caseKind']=='generated-negative-control'):
        raise ValueError('Raw acoustic negative control produced words; do not promote')


if __name__ == '__main__':
    main()
