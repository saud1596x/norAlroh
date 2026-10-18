"""Offline timing of known professional recordings, NEVER learner assessment.

The acoustic path must actually contain each label. Missing/weak labels reject
the candidate: there is no even-spacing, interpolation, wildcard or ASR prompt.
Policy thresholds below are conservative engineering filters, not calibrated
accuracy. Exported candidates still require recording-specific review.
"""
import hashlib
import json
from pathlib import Path
import unicodedata

import numpy as np

MODEL_REVISION = '088bb8afed49b11e2a29a7a9b947b479e9ef3eaa'
MODEL_SHA256 = 'b9829586625dca46c28eaf6654c7e4d6956738eb3b128c77fcb3ef9df31e5b75'
VOCAB_SHA256 = '96a92ff9bd106f825c878f502fe341f9f0488ace92d3c76dc40a6b30296efedd'


def normalize(text):
    text = unicodedata.normalize('NFC', text.replace('ٱ', 'ا'))
    return ''.join(c for c in text if unicodedata.category(c).startswith('L')
                   and c not in 'ـۥۦ').strip()


def distance(a, b):
    row = list(range(len(b) + 1))
    for i, x in enumerate(a, 1):
        new = [i]
        for j, y in enumerate(b, 1):
            new.append(min(row[j] + 1, new[-1] + 1, row[j-1] + (x != y)))
        row = new
    return row[-1]


def validate_recording_spans(spans, native_ids, duration_ms):
    """All canonical words exactly once, in order, on the real audio clock."""
    if not np.isfinite(duration_ms) or duration_ms <= 0:
        raise ValueError('Invalid real recording duration')
    if not native_ids or len(set(native_ids)) != len(native_ids):
        raise ValueError('Invalid canonical sequence')
    if (len(spans) != len(native_ids) or any(len(s) != 3 for s in spans)
            or [s[0] for s in spans] != list(native_ids)):
        raise ValueError('Recording does not cover every canonical native word in order')
    previous=0
    for _,start,end in spans:
        if (not isinstance(start,int) or not isinstance(end,int)
                or start < previous or end <= start or end > duration_ms):
            raise ValueError('Invalid, overlapping or out-of-recording acoustic interval')
        previous=end


def viterbi(logp, labels, blank=0, free_edges=False):
    """Exact CTC maximum path with repeat constraints, bounded input/memory."""
    logp = np.asarray(logp, dtype=np.float32)
    if (logp.ndim != 2 or not len(logp) or not np.isfinite(logp).all() or not labels
            or any(t == blank or t < 0 or t >= logp.shape[1] for t in labels)):
        raise ValueError('Invalid emissions/labels')
    states = np.full(2 * len(labels) + 1, blank, dtype=np.int32)
    states[1::2] = labels
    frames, count = len(logp), len(states)
    if frames * count > 20_000_000:
        raise ValueError('Align a smaller genuine audio interval')
    previous = np.full(count, -np.inf, dtype=np.float32)
    previous[0], previous[1] = logp[0, blank], logp[0, labels[0]]
    back = np.zeros((frames, count), dtype=np.uint8)
    skip_allowed = np.zeros(count, dtype=bool)
    skip_allowed[2:] = (states[2:] != blank) & (states[2:] != states[:-2])
    for frame in range(1, frames):
        one = np.r_[-np.inf, previous[:-1]]
        two = np.r_[-np.inf, -np.inf, previous[:-2]]
        two[~skip_allowed] = -np.inf
        choices = np.stack((previous, one, two))
        back[frame] = choices.argmax(axis=0)
        previous = choices.max(axis=0) + logp[frame, states]
        if free_edges:
            # An authentic introduction/closing supplication need not be
            # hallucinated as a Quran word. Only the two outside states may
            # consume arbitrary frames; all interior labels remain mandatory.
            previous[0] = choices[0,0] + logp[frame].max()
            previous[-1] = choices[:, -1].max() + logp[frame].max()
    state = count - 1 if previous[-1] > previous[-2] else count - 2
    if not np.isfinite(previous[state]): raise ValueError('No complete CTC path')
    path = np.zeros(frames, dtype=np.int32)
    for frame in range(frames - 1, -1, -1):
        path[frame] = state
        state -= int(back[frame, state])
    if state not in (0, 1): raise ValueError('Incomplete path')
    spans = []
    for i, label in enumerate(labels):
        hits = np.flatnonzero(path == 2 * i + 1)
        if not len(hits): raise ValueError('Missing acoustic label')
        spans.append((int(hits[0]), int(hits[-1]) + 1,
                      float(np.exp(logp[hits, label]).mean())))
    return spans


class Aligner:
    normalizer = staticmethod(normalize)
    def __init__(self, model_dir, threads=4):
        import onnxruntime as ort
        model_dir = Path(model_dir)
        for name, sha in [('model.int8.onnx', MODEL_SHA256), ('vocab.json', VOCAB_SHA256)]:
            if hashlib.sha256((model_dir/name).read_bytes()).hexdigest() != sha:
                raise ValueError('Pinned alignment model differs')
        self.vocab = json.loads((model_dir/'vocab.json').read_text())
        options = ort.SessionOptions(); options.intra_op_num_threads = threads
        options.inter_op_num_threads = 1
        self.model = ort.InferenceSession(str(model_dir/'model.int8.onnx'),
            sess_options=options, providers=['CPUExecutionProvider'])

    def emissions(self, values):
        return self.model.run(None, {'input_values': values[None]})[0][0]

    def align(self, pcm, words):
        """words: [(nativeID, canonical text)]. Returns measured candidate only."""
        pcm = np.asarray(pcm, dtype=np.float32)
        if (pcm.ndim != 1 or not 400 <= len(pcm) <= 1_920_000
                or not np.isfinite(pcm).all() or float(np.sqrt(np.mean(pcm**2))) < .002):
            raise ValueError('No usable bounded recording interval')
        if not words or len({word[0] for word in words}) != len(words):
            raise ValueError('Canonical native IDs must be unique')
        labels, owners, expected = [], [], []
        self.diagnostics = None
        for native_id, text in words:
            parts = [self.normalizer(w) for w in text.split()]
            if not parts or any(not p for p in parts): raise ValueError('Empty canonical word')
            for part in parts:
                if expected: labels.append(self.vocab['|']); owners.append(None)
                for char in part:
                    if char not in self.vocab: raise ValueError('Unknown canonical character')
                    labels.append(self.vocab[char]); owners.append(native_id)
                expected.append(part)
        values = (pcm - pcm.mean()) / np.sqrt(pcm.var() + 1e-7)
        logits = self.emissions(values)
        peak = logits.max(axis=-1, keepdims=True)
        logp = logits - peak - np.log(np.exp(logits-peak).sum(axis=-1,keepdims=True))
        measured = viterbi(logp, labels, free_edges=True)
        decoded = logp[measured[0][0]:measured[-1][1]].argmax(axis=-1)
        greedy = [int(t) for i,t in enumerate(decoded)
                  if t != 0 and (i == 0 or t != decoded[i-1])]
        target = [t for t in labels if t != self.vocab['|']]
        observed = [t for t in greedy if t != self.vocab['|']]
        cer = distance(target, observed) / max(1, len(target))
        reverse = {v:k for k,v in self.vocab.items()}
        self.diagnostics = {'greedy':''.join(reverse[t] for t in greedy),
                            'canonical':' '.join(expected),'greedyCER':cer,
                            'measuredStartFrame':measured[0][0],'measuredEndFrame':measured[-1][1]}
        if cer > .45: raise ValueError(f'Acoustic transcript disagrees ({cer:.3f})')
        result = {}
        for owner, (first,last,confidence) in zip(owners, measured):
            if owner is None: continue
            # Output frame clock uses 320-sample stride. Do not expand the
            # receptive field into an adjacent word's measured interval.
            start, end = first * 20, min(round(len(pcm)/16), last*20)
            entry = result.setdefault(owner, [start,end,[]])
            entry[1] = end;entry[2].append(confidence)
        spans, qualities, weak = [], [], []
        for owner, (start,end,scores) in result.items():
            quality = float(np.mean(scores))
            if quality < .35 or end <= start: weak.append(owner)
            spans.append([owner,start,end]);qualities.append(quality)
        self.diagnostics['wordPosteriors']={str(owner):float(np.mean(entry[2])) for owner,entry in result.items()}
        self.diagnostics['weakNativeIDs']=weak
        self.diagnostics['measuredSpans']=spans
        if weak:raise ValueError('Weak/empty acoustic word')
        if len(spans) != len(words): raise ValueError('Incomplete canonical binding')
        return {'spans':spans,'greedyCER':cer,'minimumWordPosterior':min(qualities),
                'status':'MEASURED_CANDIDATE_REQUIRES_REVIEW',
                'modelRevision':getattr(self,'revision',MODEL_REVISION)}
