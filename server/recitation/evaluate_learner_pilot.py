"""Local, audio-only diagnostic on separately licensed learner fixtures.

Intended ayah text and coarse error categories are NOT verbatim transcripts.
They are never passed to a decoder and cannot establish WER, error recall,
Tajweed quality, speaker generalization or superiority over another product.
No training, upload, corpus redistribution or model download occurs here.
"""
import argparse
import hashlib
import json
from pathlib import Path
import time
import numpy as np
from faster_whisper.audio import decode_audio
from noor_engine.corpus import Corpus
from noor_engine.inference import Recognizer


def windows(samples):
    """Actual low-latency capture cadence: first2s, stride1s, last8s."""
    ends = list(range(32_000, len(samples) + 1, 16_000))
    if not ends or ends[-1] != len(samples): ends.append(len(samples))
    for end in ends:
        start = max(0, end - 128_000)
        yield start, end, samples[start:end].copy()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--model', type=Path, required=True)
    parser.add_argument('--corpus-root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--max-seconds', type=int, default=300)
    args = parser.parse_args()
    if not 1 <= args.max_seconds <= 600: raise ValueError('Bounded local diagnostic required')
    manifest_bytes = args.manifest.read_bytes()
    manifest = json.loads(manifest_bytes)
    if not 1 <= len(manifest['cases']) <= 24: raise ValueError('Small source-pinned pilot required')
    recognizer = Recognizer(args.model, cpu_threads=2)
    recognizer.load()
    corpus = Corpus(args.corpus_root)
    report = {'status': 'INCOMPLETE', 'fixtureManifestSHA256': hashlib.sha256(manifest_bytes).hexdigest(),
        'model': recognizer.model_id, 'modelRevision': recognizer.revision, 'runtime': 'faster-whisper/int8/cpu2',
        'selection': manifest['selection'], 'source': manifest['source'],
        'expectedCases': len(manifest['cases']), 'cases': [],
        'limits': 'Coarse annotations/intended text are not verbatim speech; no calibrated error or Tajweed score, speaker-heldout claim, iOS microphone result, training or model promotion',
        'learnerErrorAccuracy': None, 'tajweedAccuracy': None, 'comparedWithTarteel': False}
    args.output.parent.mkdir(parents=True, exist_ok=True)

    def checkpoint():
        temporary = args.output.with_suffix('.pending')
        temporary.write_bytes((json.dumps(report, ensure_ascii=False, indent=2, allow_nan=False)+'\n').encode())
        temporary.replace(args.output)

    started = time.monotonic()
    checkpoint()
    for index, case in enumerate(manifest['cases']):
        if time.monotonic() - started >= args.max_seconds: break
        if case['riwayah'] != 'Hafs': raise ValueError('Pilot must match this app edition')
        file = (args.manifest.parent/'clips'/case['file']).resolve()
        file.relative_to((args.manifest.parent/'clips').resolve())
        if hashlib.sha256(file.read_bytes()).hexdigest() != case['audio_sha256']:
            raise ValueError('Original learner fixture bytes changed')
        samples = decode_audio(str(file), sampling_rate=16_000)
        if not 400 <= len(samples) <= 16_000 * 60: raise ValueError('Unexpected full fixture extent')
        current = {'case': case['file'], 'sha256': case['audio_sha256'], 'durationSeconds': len(samples)/16_000,
                   'sourceRecordingGroup': case['source_recording_group'], 'windows': [], 'status': 'INCOMPLETE'}
        report['cases'].append(current)
        checkpoint()
        for start, end, original in windows(samples):
            if time.monotonic()-started >= args.max_seconds: break
            pcm_digest = hashlib.sha256(original.astype('<f4').tobytes()).hexdigest()
            result = recognizer._decode(original)
            # Never join words across an actual rejected-word boundary.
            runs = {}
            for word in result['words']: runs.setdefault(word['run_index'], []).append(word)
            locations = [binding for run in runs.values() for binding in corpus.align(run)]
            current['windows'].append({'startFrame': start, 'endFrame': end, 'sourcePCMSHA256': pcm_digest,
                'rawObservations': result['observations'], 'acceptedWords': result['words'],
                'candidateBindings': locations, 'unresolved': result['unresolved'],
                'inferenceMilliseconds': result['inference_ms'], 'configuration': result['processing_configuration']})
            if pcm_digest != hashlib.sha256(original.astype('<f4').tobytes()).hexdigest():
                raise ValueError('Recognizer modified original PCM')
            checkpoint()
        if current['windows'] and current['windows'][-1]['endFrame'] == len(samples):
            current['status'] = 'COMPLETED_DIAGNOSTIC'
            # This annotation is attached AFTER every audio-only decode.
            current['intendedVerse'] = case['verse']
            current['intendedReference_NOT_VERBATIM'] = case['intended_reference']
            current['publisherErrorCategories_NOT_VERIFIED_TIMINGS'] = case['annotated_errors']
        checkpoint()
        print(case['file'], current['status'], 'windows', len(current['windows']), flush=True)
    if len(report['cases']) == report['expectedCases'] and all(c['status'] == 'COMPLETED_DIAGNOSTIC' for c in report['cases']):
        report['status'] = 'COMPLETED_DIAGNOSTIC_NOT_ACCEPTANCE'
    checkpoint()
    print(report['status'], flush=True)


if __name__ == '__main__': main()
