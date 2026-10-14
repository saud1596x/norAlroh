"""Independent CPU benchmark on public reciter fixtures, not a shipped backend.

Compare ordinary and quiet speech plus silence/noise without a Quran prompt.
No user recording is read or uploaded. A passing CPU test cannot certify the
Core ML conversion, live iPhone input, Tajweed, or superiority to another app.
"""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import time
import unicodedata
import urllib.request

MODEL = 'OdyAsh/faster-whisper-base-ar-quran'
REVISION = '8578bafd427d122f671b187706650e76edf6f86f'
ROOT = Path(__file__).resolve().parents[2]


def words(text):
    expanded = text.replace('ٱ', 'ا')
    return [''.join(c for c in unicodedata.normalize('NFKD', part)
                    if c.isalpha() and c not in 'ـۥۦ')
            for part in expanded.split() if any(c.isalpha() for c in part)]


def edits(expected, actual):
    row = list(range(len(actual) + 1))
    for i, word in enumerate(expected, 1):
        following = [i]
        for j, heard in enumerate(actual, 1):
            following.append(min(following[-1] + 1, row[j] + 1,
                                 row[j - 1] + (word != heard)))
        row = following
    return row[-1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    import numpy as np
    from faster_whisper import WhisperModel
    from faster_whisper.audio import decode_audio
    from huggingface_hub import snapshot_download

    args.output.mkdir(parents=True, exist_ok=True)
    model_path = snapshot_download(MODEL, revision=REVISION,
                                  allow_patterns=['*.json', '*.bin', 'vocabulary.*'])
    model = WhisperModel(model_path, device='cpu', compute_type='int8',
                         cpu_threads=1, num_workers=1)
    fixtures = json.loads((ROOT / 'tools/RecitationEngineProbe/fixtures/sources.json').read_text())
    script = json.loads((ROOT / 'content-sources/recitation-word-script.json').read_text(encoding='utf-8'))
    reference = {key: ' '.join(token for group in groups for token in group[2])
                 for key, groups in script['groups'].items()}
    results = []
    controls = [('silence', np.zeros(128000, dtype=np.float32)),
                ('quiet-noise', np.random.default_rng(14).normal(0, 0.001, 128000).astype(np.float32))]
    for fixture in fixtures:
        target = args.output / fixture['file']
        if not target.is_file() or hashlib.sha256(target.read_bytes()).hexdigest() != fixture['sha256']:
            if not fixture['url'].startswith('https://everyayah.com/data/'):
                raise ValueError('Unexpected reference-audio destination')
            with urllib.request.urlopen(fixture['url'], timeout=60) as response:
                raw = response.read(2_000_001)
            if len(raw) > 2_000_000 or hashlib.sha256(raw).hexdigest() != fixture['sha256']:
                raise ValueError('Reference audio integrity mismatch')
            target.write_bytes(raw)
        samples = decode_audio(str(target), sampling_rate=16000)
        for gain in [1.0, 0.03]:
            controls.append((f'{fixture["verse"]}/gain={gain}', samples * gain))
    for name, samples in controls:
        start = time.monotonic()
        segments, _ = model.transcribe(samples, language='ar', beam_size=1,
                                      condition_on_previous_text=False, word_timestamps=True,
                                      vad_filter=False, temperature=0)
        segments = list(segments)
        text = ' '.join(s.text for s in segments)
        actual = words(text)
        key = name.split('/')[0]
        expected = words(reference[key]) if key in reference else []
        results.append({'case': name, 'durationSeconds': len(samples) / 16000,
                        'inferenceSeconds': time.monotonic() - start,
                        'peak': float(np.max(np.abs(samples))),
                        'rms': float(np.sqrt(np.mean(samples ** 2))),
                        'referenceWordCount': len(expected), 'recognizedWordCount': len(actual),
                        'editCount': edits(expected, actual),
                        'wordErrorRate': edits(expected, actual) / len(expected) if expected else None,
                        'controlHallucination': bool(actual) if not expected else None,
                        'noSpeechProbabilities': [s.no_speech_prob for s in segments]})
        (args.output / 'report.json').write_text(json.dumps({
            'model': MODEL, 'revision': REVISION, 'platform': platform.platform(),
            'wordErrorRateReference': 'Pinned Imlaei lexical correspondence; Arabic marks normalized',
            'scope': 'Public-reference CPU transcription baseline, not live iPhone or pronunciation grading',
            'cases': results}, indent=2) + '\n')
        print(name, 'reference=', len(expected), 'recognized=', len(actual),
              'edits=', results[-1]['editCount'], flush=True)


if __name__ == '__main__':
    main()
