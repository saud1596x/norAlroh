"""Provisional lexical differences between independent exact acoustic anchors.

Never equate one ASR discrepancy with a confirmed learner mistake. Missing
audio, a long pause, uncertain words and ambiguous passage locations produce no
observation. No pronunciation/Tajweed correctness can be inferred here.
"""
import hashlib
from .corpus import normalize


def candidates(corpus, heard, aligned):
    ordered = sorted(aligned, key=lambda e:(e['start'], e['end'], e['native_id']))
    results = {}
    for left, right in zip(ordered, ordered[1:]):
        if left['verse'] != right['verse'] or right['start']-left['end'] > 2: continue
        first, last = corpus.by_id[left['native_id']], corpus.by_id[right['native_id']]
        if last <= first or last-first > 6: continue
        middle = [w for w in heard if w['start'] >= left['end']-.001 and w['end'] <= right['start']+.001]
        if any(w['confidence'] < .95 for w in middle): continue
        expected = corpus.words[first+1:last]
        if not expected and not middle: continue
        if expected and middle and len(expected) == len(middle): kind = 'possible_substitution'
        elif expected and not middle: kind = 'possible_omission'
        elif not expected and middle: kind = 'possible_addition'
        else: kind = 'unresolved_word_difference'
        # Equal lexical forms can still be a timestamp boundary artifact. Do
        # not report a discrepancy when their full exact forms agree.
        tokens = tuple(normalize(w['text']) for w in middle)
        forms = {()}
        for word in expected: forms = {a+b for a in forms for b in word.aliases}
        if tokens in forms: continue
        identity = f"{kind}:{left['native_id']}:{right['native_id']}:{left['end']:.2f}:{right['start']:.2f}"
        identity = hashlib.sha256(identity.encode()).hexdigest()[:24]
        results[identity] = {'observation_id':identity, 'category':kind, 'verse':left['verse'],
            'reference_ids':[w.native_id for w in expected], 'start':left['end'], 'end':right['start'],
            'state':'provisional', 'requires_review':True, 'is_confirmed_recitation_error':False}
    return list(results.values())
