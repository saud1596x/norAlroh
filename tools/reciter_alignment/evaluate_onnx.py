"""Real public PCM parity/latency of an experimental independent raw CTC.

No forced alignment, canonical-text prompt, private audio or cloud inference.
"""
import argparse
import hashlib
import json
from pathlib import Path
import time

import numpy as np
from faster_whisper.audio import decode_audio
from quran_ctc import QuranAligner, REVISION
from quran_onnx import QuranONNXAligner, EXPORT_SHA256, collapse_words


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--model', type=Path, required=True)
    parser.add_argument('--onnx', type=Path, required=True)
    parser.add_argument('--fixtures', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    root = Path(__file__).resolve().parents[2]
    sources = json.loads((root/'tools/RecitationEngineProbe/fixtures/sources.json').read_text())
    gpu = QuranONNXAligner(args.model, args.onnx, profile_prefix=args.output/'cuda-profile')
    # Original non-quantized CPU model, to isolate export/FP16 from the old
    # dynamic-int8 alignment implementation. Actual PCM is identical for both.
    import torch
    from transformers import Wav2Vec2ForCTC
    torch.set_num_threads(4)
    cpu = Wav2Vec2ForCTC.from_pretrained(str(args.model), local_files_only=True,
        use_safetensors=True, attn_implementation='eager').eval()
    cases = []
    for fixture in sources:
        path = args.fixtures/fixture['file']
        if hashlib.sha256(path.read_bytes()).hexdigest() != fixture['sha256']:
            raise ValueError('Public fixture differs')
        pcm = decode_audio(str(path), sampling_rate=16000)
        for gain in (1., .03):
            cases.append((fixture['verse'] + f'/gain={gain}', pcm*np.float32(gain)))
    cases += [('silence', np.zeros(16000, dtype=np.float32)),
              ('seeded-noise', np.random.default_rng(14).normal(0, .001, 16000).astype(np.float32))]
    results = []
    for name, pcm in cases:
        values = (pcm-pcm.mean())/np.sqrt(pcm.var()+1e-7)
        started = time.monotonic()
        actual = gpu.emissions(values)
        elapsed = time.monotonic()-started
        with torch.inference_mode():
            logits = cpu(torch.from_numpy(values[None])).logits[0].numpy()
        peak = logits.max(axis=-1, keepdims=True)
        probabilities = np.exp(logits-peak)
        probabilities /= probabilities.sum(axis=-1, keepdims=True)
        projected = np.zeros_like(actual)
        for char, source_id in gpu.source_vocab.items():
            target = gpu.vocab['|'] if char == '|' else gpu.vocab.get(gpu.normalizer(char), 0) if len(char) == 1 else 0
            projected[:, target] += probabilities[:, source_id]
        expected = np.log(np.maximum(projected, 1e-30))
        left, right = collapse_words(actual, gpu.vocab, len(pcm)), collapse_words(expected, gpu.vocab, len(pcm))
        result = {'case': name, 'audioSeconds': len(pcm)/16000, 'gpuSeconds': elapsed,
            'greedyWordsEqual': [w['text'] for w in left] == [w['text'] for w in right],
            'frameLabelAgreement': float(np.mean(actual.argmax(axis=-1) == expected.argmax(axis=-1))),
            'maxPosteriorDifference': float(np.abs(np.exp(actual)-np.exp(expected)).max()),
            'rawGPUWords': left, 'rawCPUWords': right}
        results.append(result)
        print(name, 'greedyEqual', result['greedyWordsEqual'], 'gpuSeconds', round(elapsed, 4), flush=True)
    profile_path = Path(gpu.model.end_profiling())
    profile = json.loads(profile_path.read_text())
    providers = {}
    for node in profile:
        provider = node.get('args', {}).get('provider')
        if provider:
            providers[provider] = providers.get(provider, 0)+1
    if not providers.get('CUDAExecutionProvider'):
        raise RuntimeError('No actual CUDA node execution')
    report = {'scope': 'EXPERIMENTAL_RAW_CTC_PUBLIC_AUDIO_EXPORT_PARITY_ONLY',
        'sourceRevision': REVISION, 'exportSHA256': EXPORT_SHA256,
        'sources': sources, 'executedNodes': providers, 'cases': results,
        'productionApproved': False, 'phoneIntegration': 'NOT_IMPLEMENTED',
        'naturalLearnerQuality': 'NOT_ESTABLISHED', 'forcedAlignmentUsed': False}
    (args.output/'report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')


if __name__ == '__main__':
    main()
