"""Compare actual whole public audio to context-window CTC on its real clock."""
import argparse
import hashlib
import json
from pathlib import Path
import time
import urllib.request

import numpy as np
from faster_whisper.audio import decode_audio
from audit import exact_record
from quran_onnx import QuranONNXAligner, collapse_words


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--model', type=Path, required=True)
    parser.add_argument('--onnx', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--reciter', type=int, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--precision', choices=('float16', 'float32'), required=True)
    parser.add_argument('--window-mode', choices=('whole', 'experimental-context-stitch1'), required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    source_report = json.loads(args.report.read_text(encoding='utf-8'))
    reciter = next(r for r in json.loads((root/'ios/Athar/haramain-reciters.json').read_text(encoding='utf-8'))['reciters']
                   if r['id'] == args.reciter)
    source = next(r for r in source_report['records'] if r['reciterID'] == args.reciter)
    if source_report['surah'] != 1 or not exact_record(source, reciter, 1):
        raise ValueError('Only an exact previously hashed public Fatiha recording')
    args.output.mkdir(parents=True, exist_ok=True)
    path = args.output/'development-public-reference.mp3'
    created = False
    try:
        with path.open('xb') as sink:
            created = True
            with urllib.request.urlopen(source['audioURL'], timeout=30) as response:
                raw = response.read(8_000_001)
            if len(raw) > 8_000_000 or hashlib.sha256(raw).hexdigest() != source['audioSHA256']:
                raise ValueError('Public recording exceeds bound or differs from its actual source hash')
            sink.write(raw)
        pcm = decode_audio(str(path), sampling_rate=16000)
        if not 480_000 < len(pcm) <= 1_920_000:
            raise ValueError('Need a real30..120second recording, never padded acceptance')
        values = (pcm-pcm.mean())/np.sqrt(pcm.var()+1e-7)
        gpu = QuranONNXAligner(args.model, args.onnx, precision=args.precision,
                              window_mode=args.window_mode)
        started = time.monotonic(); actual = gpu.emissions(values); gpu_seconds = time.monotonic()-started
        import torch
        from transformers import Wav2Vec2ForCTC
        torch.set_num_threads(4)
        model = Wav2Vec2ForCTC.from_pretrained(str(args.model), local_files_only=True,
            use_safetensors=True, attn_implementation='eager').eval()
        started = time.monotonic()
        with torch.inference_mode():
            logits = model(torch.from_numpy(values[None])).logits[0].numpy()
        cpu_seconds = time.monotonic()-started
        probabilities = np.exp(logits-logits.max(axis=-1, keepdims=True))
        probabilities /= probabilities.sum(axis=-1, keepdims=True)
        projected = np.zeros_like(actual)
        for char, source_id in gpu.source_vocab.items():
            target = gpu.vocab['|'] if char == '|' else gpu.vocab.get(gpu.normalizer(char), 0) if len(char) == 1 else 0
            projected[:, target] += probabilities[:, source_id]
        expected = np.log(np.maximum(projected, 1e-30))
        left, right = collapse_words(actual, gpu.vocab, len(pcm)), collapse_words(expected, gpu.vocab, len(pcm))
        same_words = [w['text'] for w in left] == [w['text'] for w in right]
        drift = max((abs(a[k]-b[k]) for a,b in zip(left,right) for k in ['start','end']), default=0) if same_words else None
        report = {'scope': 'ACTUAL_LONG_PUBLIC_RECORDING_CHUNK_CLOCK_COMPARISON_NOT_ACCEPTANCE',
            'source': {k: source[k] for k in ['reciterID','recordingID','audioURL','audioSHA256']},
            'audioSeconds': len(pcm)/16000, 'runtime': gpu.runtime_identity,
            'gpuColdSeconds': gpu_seconds, 'cpuWholeSeconds': cpu_seconds,
            'sameGreedyWords': same_words, 'maximumWordBoundaryDifferenceSeconds': drift,
            'maximumFramePosteriorDifference': float(np.abs(np.exp(actual)-projected).max()),
            'frameLabelAgreement': float(np.mean(actual.argmax(axis=-1) == expected.argmax(axis=-1))),
            'gpuWords': left, 'cpuWords': right, 'outputFrameCount': len(actual),
            'exactStrideFrameCount': (len(pcm)-400)//320+1,
            'sourceHashes': {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                             for p in [Path(__file__), Path(__file__).with_name('quran_onnx.py')]},
            'productionApproved': False, 'naturalLearnerAccuracy': 'NOT_ESTABLISHED'}
        (args.output/'report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
        print(json.dumps({k:v for k,v in report.items() if k not in ['gpuWords','cpuWords']}), flush=True)
    finally:
        if created:
            path.unlink()


if __name__ == '__main__':
    main()
