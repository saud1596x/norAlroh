"""Independent raw acoustic CTC and optional professional alignment on CUDA.

Development only. No reference text is accepted by recognize(). Its measured
CTC posterior is not calibrated correctness. It cannot assess Tajweed. The
inherited align() method is exclusively for known professional recordings.
"""
import hashlib
import json
from importlib import metadata
from pathlib import Path
import time

import numpy as np
from quran_ctc import QuranAligner, REVISION, verify_assets
from ctc import read_vocabulary

EXPORT_SHA256 = 'a1dbb6be2a521c233cbb35f7a00c5016539b14e2750bb5708b21cec19cd9c333'
EXPORTS = {
    'float16': EXPORT_SHA256,
    'float32': 'd854e74fe2726495e2f2a2d34dccdb46ef75ae2c681e6a7fae5ee0ee30f9c4c2',
}


def inference_identity(precision, window_mode):
    if precision not in EXPORTS or window_mode not in ('whole', 'experimental-context-stitch1'):
        raise ValueError('Explicit pinned precision and acoustic window mode required')
    # A restored or upgraded CUDA/cuDNN library can change kernel results even
    # when the ONNX file and ORT version match. Never resume its acoustic
    # measurements under the previous library identity. Unpackaged installs
    # remain explicit; CUDA availability is still checked by the real session.
    versions = []
    for package in ('nvidia-cuda-runtime-cu12', 'nvidia-cublas-cu12', 'nvidia-cudnn-cu12',
                    'nvidia-cufft-cu12', 'nvidia-curand-cu12', 'nvidia-cuda-nvrtc-cu12'):
        try:
            value = metadata.version(package)
        except metadata.PackageNotFoundError:
            value = 'unpackaged'
        versions.append(package + '=' + value)
    libraries = ','.join(versions)
    return f'onnxruntime1.26.0/cuda-{precision}/{EXPORTS[precision]}/{window_mode}/arena-same-as-requested-5gb1/shrink-gpu0-after-run1/libraries[{libraries}]'


class InferenceIntervalLimit(RuntimeError):
    """A development resource limit, not evidence of bad recitation/alignment."""


class InferenceWorkDeadline(RuntimeError):
    """No additional acoustic chunk may start after the local work deadline."""


def acoustic_windows(samples):
    """Exact Wav2Vec2 stride320/receptive400 clock, with two-second context.

    Keep each output frame exactly once. No padding, interpolated logits,
    shifted word times, omitted audio, or conditioning on the expected text.
    Noncausal edge context can change hypotheses; acoustic review still applies.
    """
    if type(samples) is not int or not 400 <= samples <= 1_920_000:
        raise InferenceIntervalLimit('Bounded acoustic interval requires400samples..120seconds')
    frames = (samples-400)//320+1
    if samples <= 480_000:
        return [(0, frames, 0, samples, 0, frames)]
    windows = []
    for first in range(0, frames, 750):
        end = min(frames, first+750)
        context_first, context_end = max(0, first-100), min(frames, end+100)
        windows.append((first, end, context_first*320, (context_end-1)*320+400,
                        first-context_first, end-context_first))
    return windows


def acoustic_logits(values, decode, deadline=None):
    pieces = []
    for first, end, begin_sample, end_sample, crop_start, crop_end in acoustic_windows(len(values)):
        if deadline is not None and time.monotonic() >= deadline:
            raise InferenceWorkDeadline('Local limit reached before starting another acoustic chunk')
        chunk = decode(values[begin_sample:end_sample])
        expected = (end_sample-begin_sample-400)//320+1
        if chunk.ndim != 2 or len(chunk) != expected or not np.isfinite(chunk).all():
            raise ValueError('Acoustic decoder frame clock differs from actual chunk')
        part = chunk[crop_start:crop_end]
        if len(part) != end-first:
            raise ValueError('Incomplete acoustic output interval')
        pieces.append(part)
    return np.concatenate(pieces, axis=0)


def collapse_words(logp, vocab, samples):
    """Greedy source words, no dictionary/prompt/forced canonical spelling."""
    logp = np.asarray(logp)
    if (logp.ndim != 2 or not len(logp) or logp.shape[1] != len(vocab)
            or not np.isfinite(logp).all() or not 400 <= samples <= 1_920_000):
        raise ValueError('Invalid bounded CTC emissions/audio')
    reverse = {i: c for c, i in vocab.items()}
    if len(reverse) != len(vocab) or vocab.get('<pad>') != 0 or '|' not in vocab:
        raise ValueError('Invalid CTC vocabulary')
    labels = logp.argmax(axis=-1)
    symbols = []
    for frame, raw in enumerate(labels):
        label = int(raw)
        if label == 0:
            continue
        confidence = float(np.exp(logp[frame, label]))
        if frame and labels[frame - 1] == label:
            symbols[-1]['end'] = frame + 1
            symbols[-1]['posteriors'].append(confidence)
        else:
            symbols.append({'label': label, 'start': frame, 'end': frame + 1,
                            'posteriors': [confidence]})
    result, pending = [], []

    def finish():
        if not pending:
            return
        start = pending[0]['start'] * .02
        end = min(samples / 16000, pending[-1]['end'] * .02)
        if end <= start:
            raise ValueError('CTC source word outside captured audio')
        result.append({'text': ''.join(reverse[s['label']] for s in pending),
                       'start': start, 'end': end,
                       'posterior': float(np.mean([p for s in pending for p in s['posteriors']])),
                       'timing_source': 'raw-ctc-20ms-stride',
                       'recognition_state': 'unvalidated-independent-hypothesis'})
        pending.clear()

    for symbol in symbols:
        if symbol['label'] == vocab['|']:
            finish()
        else:
            pending.append(symbol)
    finish()
    return result


class QuranONNXAligner(QuranAligner):
    def __init__(self, model_dir, onnx_dir, threads=4, profile_prefix=None,
                 precision='float16', window_mode='whole'):
        import onnxruntime as ort
        identity = inference_identity(precision, window_mode)
        if ort.__version__ != '1.26.0':
            raise ValueError('Use the evaluated pinned ONNX Runtime1.26.0')
        model_dir, onnx_dir = Path(model_dir), Path(onnx_dir)
        verify_assets(model_dir)
        model = onnx_dir / 'quran-ctc.onnx'
        if model.is_symlink() or not model.is_file():
            raise ValueError('Missing/linked pinned ONNX export')
        sha = hashlib.sha256()
        with model.open('rb') as source:
            for part in iter(lambda: source.read(1024 * 1024), b''):
                sha.update(part)
        if sha.hexdigest() != EXPORTS[precision]:
            raise ValueError('ONNX export differs from evaluated artifact')
        self.source_vocab = read_vocabulary(model_dir / 'vocab.json')
        letters = sorted({self.normalizer(c) for c in self.source_vocab
                          if len(c) == 1 and self.normalizer(c) and c != '|'})
        self.vocab = {'<pad>': 0, '|': 1, **{c: i + 2 for i, c in enumerate(letters)}}
        options = ort.SessionOptions()
        options.intra_op_num_threads = threads
        options.inter_op_num_threads = 1
        if profile_prefix is not None:
            options.enable_profiling = True
            options.profile_file_prefix = str(profile_prefix)
        self.model = ort.InferenceSession(str(model), sess_options=options,
            # The 3GB trial exposed an actual allocation refusal (131MB free
            # inside its arena versus321MB requested). Keep a bounded5GB arena
            # on the existing8GB development GPU; never relax acoustic filters.
            providers=[('CUDAExecutionProvider', {'gpu_mem_limit': 5 * 1024**3,
                'arena_extend_strategy': 'kSameAsRequested',
                'cudnn_conv_algo_search': 'HEURISTIC', 'cudnn_conv_use_max_workspace': '0',
                'use_tf32': '0'}), 'CPUExecutionProvider'])
        self.run_options = ort.RunOptions()
        # Actual long-surah passes exposed arena accumulation after142ayahs.
        # Shrink unused CUDA blocks between completed runs instead of retaining
        # every former shape. Weights/precision/acoustic thresholds are unchanged.
        self.run_options.add_run_config_entry('memory.enable_memory_arena_shrinkage', 'gpu:0')
        if self.model.get_providers()[0] != 'CUDAExecutionProvider':
            raise RuntimeError('CUDA unavailable; refusing silent CPU fallback')
        self.device = f'cuda-onnx-{precision}'
        self.revision = REVISION
        self.runtime_identity = identity
        self.window_mode = window_mode
        self.deadline = None

    def emissions(self, values):
        values = np.asarray(values, dtype=np.float32)
        if values.ndim == 1 and len(values) > 1_920_000:
            raise InferenceIntervalLimit('CUDA evaluation currently limits one interval to120seconds')
        if (values.ndim != 1 or len(values) < 400 or not np.isfinite(values).all()):
            raise ValueError('CUDA evaluation requires finite mono PCM with at least400samples')
        decode = lambda chunk: self.model.run(['logits'], {'input_values': chunk[None]}, self.run_options)[0][0]
        if self.deadline is not None and time.monotonic() >= self.deadline:
            raise InferenceWorkDeadline('Local limit reached before another acoustic interval')
        if self.window_mode == 'experimental-context-stitch1':
            logits = acoustic_logits(values, decode, self.deadline)
        else:
            # Global attention makes independently chunked logits different from
            # whole-interval inference. Never silently substitute that experiment.
            if len(values) > 720_000:
                raise InferenceIntervalLimit('Whole GPU evaluation limits an interval to45seconds')
            logits = decode(values)
            if logits.ndim != 2 or len(logits) != (len(values)-400)//320+1:
                raise ValueError('Whole decoder differs from original acoustic frame clock')
        if not np.isfinite(logits).all():
            raise ValueError('Nonfinite independent acoustic output')
        peak = logits.max(axis=-1, keepdims=True)
        probabilities = np.exp(logits - peak)
        probabilities /= probabilities.sum(axis=-1, keepdims=True)
        projected = np.zeros((len(logits), len(self.vocab)), dtype=np.float32)
        for char, source_id in self.source_vocab.items():
            target = self.vocab['|'] if char == '|' else self.vocab.get(self.normalizer(char), 0) if len(char) == 1 else 0
            projected[:, target] += probabilities[:, source_id]
        return np.log(np.maximum(projected, 1e-30))

    def recognize(self, pcm):
        pcm = np.asarray(pcm, dtype=np.float32)
        if (pcm.ndim != 1 or not 400 <= len(pcm) <= 480_000 or not np.isfinite(pcm).all()
                or np.max(np.abs(pcm)) > 1):
            raise ValueError('Invalid normalized mono PCM')
        if np.sqrt(np.mean(pcm.astype(np.float64)**2)) < .00001:
            return []
        values = (pcm - pcm.mean()) / np.sqrt(pcm.var() + 1e-7)
        return collapse_words(self.emissions(values), self.vocab, len(pcm))
