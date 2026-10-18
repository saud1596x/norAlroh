"""Bounded Mac-only independent CTC conversion and actual public-PCM parity.

No expected passage or forced alignment enters either recognizer. A successful
conversion does not establish learner accuracy, iPhone performance or release
approval. The original source and both converted variants are compared on the
same actual samples before any package can be considered for app integration.
"""
import argparse
import hashlib
import json
from pathlib import Path
import platform
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
    import av
    frames = []
    with av.open(str(path)) as container:
        resampler = av.audio.resampler.AudioResampler(format='fltp', layout='mono', rate=16000)
        for frame in container.decode(audio=0):
            frames.extend(value.to_ndarray().reshape(-1) for value in resampler.resample(frame))
        frames.extend(value.to_ndarray().reshape(-1) for value in resampler.resample(None))
    values = np.concatenate(frames).astype(np.float32)
    if not 400 <= len(values) <= 256000 or not np.isfinite(values).all():
        raise ValueError('Actual public clip outside bounded 16second conversion scope')
    return values


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
    args = parser.parse_args()
    if platform.system() != 'Darwin':
        raise ValueError('Actual Core ML prediction is required; conversion-only output is insufficient')
    args.output.mkdir(parents=True, exist_ok=True)
    receipt_path = args.output / 'actual-conversion.json'
    if receipt_path.exists():
        raise ValueError('Do not overwrite a previous conversion/evaluation receipt')
    report = {'scope': 'INDEPENDENT_CTC_COREML_CONVERSION_NOT_LEARNER_ACCEPTANCE',
              'sourceRevision': REVISION, 'sourceFiles': FILES, 'productionApproved': False,
              'phoneIntegrated': False, 'expectedTextPrompt': False, 'forcedAlignment': False,
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
    import coremltools.optimize.coreml as cto
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
        compute_precision=ct.precision.FLOAT32, minimum_deployment_target=ct.target.iOS17,
        compute_units=ct.ComputeUnit.CPU_AND_GPU)
    float_path = args.output/'quran-ctc-float32.mlpackage'
    converted.save(str(float_path))
    print('NOOR_CTC_COREML_FLOAT_PACKAGE_READY', flush=True)
    config = cto.OptimizationConfig(global_config=cto.OpLinearQuantizerConfig(
        mode='linear_symmetric', dtype='int8', weight_threshold=512))
    compressed = cto.linear_quantize_weights(converted, config=config)
    int8_path = args.output/'quran-ctc-int8.mlpackage'
    compressed.save(str(int8_path))
    print('NOOR_CTC_COREML_COMPRESSED_PACKAGE_READY', flush=True)
    source_vocab = json.loads((args.model/'vocab.json').read_text())
    normalizer = object.__new__(QuranAligner).normalizer
    letters = sorted({normalizer(c) for c in source_vocab if len(c) == 1 and normalizer(c) and c != '|'})
    vocab = {'<pad>': 0, '|': 1, **{c:i+2 for i,c in enumerate(letters)}}
    root = Path(__file__).resolve().parents[2]
    # Two exact public files already reviewed and present in the test bundle.
    for name, pin in FIXTURES.items():
        clip = root/'ios/AtharTests/RecitationFixtures'/f'{name}.mp3'
        if clip.is_symlink() or digest(clip) != pin:
            raise ValueError('Actual public parity fixture changed')
        original = load_pcm(clip)
        for length in sorted({min(32000, len(original)), len(original)}):
            pcm = original[:length]
            conditioned = ((pcm-pcm.mean())/np.sqrt(pcm.var()+1e-7)).astype(np.float32)[None]
            with torch.inference_mode():
                expected = wrapper(torch.from_numpy(conditioned)).numpy()[0]
                traced_result = traced(torch.from_numpy(conditioned)).numpy()[0]
            expected = project(expected, source_vocab, vocab)
            if not np.allclose(expected, project(traced_result,source_vocab,vocab), atol=1e-5):
                raise ValueError('Traced source changed actual variable-length acoustic output')
            for variant, candidate in [('float32', converted), ('weight-int8', compressed)]:
                before = time.monotonic()
                actual = candidate.predict({'input_values': conditioned})['logits'][0]
                elapsed = time.monotonic()-before
                if actual.shape[0] != (length-400)//320+1 or not np.isfinite(actual).all():
                    raise ValueError('Converted output differs from actual frame clock')
                actual = project(actual, source_vocab, vocab)
                report['cases'].append({'sourceFile':name+'.mp3','sourceSHA256':digest(clip),
                    'originalFrames':len(original),'decodedFrames':length,'variant':variant,
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
        for variant,folder in [('float32',float_path),('weight-int8',int8_path)]]
    save()
    print('NOOR_CTC_COREML_RESULT',json.dumps(report,ensure_ascii=False),flush=True)
    if not report['allRawWordsEqual']:
        raise ValueError('Actual raw words changed after conversion/compression; do not promote')


if __name__ == '__main__':
    main()
