"""Decoder boundary fixtures; these test policy, not acoustic accuracy."""
from types import SimpleNamespace
from pathlib import Path
import numpy as np
from noor_engine.inference import Recognizer
from noor_engine.protocol import AudioHeader, SessionIntelligence
from noor_engine.corpus import Corpus


def decode(words, no_speech=.01):
    recognizer = Recognizer(Path('.'))
    class Model:
        def transcribe(self, samples, **options):
            return [SimpleNamespace(no_speech_prob=no_speech, words=words)], None
    recognizer.model = Model()
    # Alternating values exercise only word gating, never actual ASR evidence.
    return recognizer._decode(np.tile(np.array([.06, -.06], dtype=np.float32), 32000))


def word(text, start, probability=.99, end=None):
    return SimpleNamespace(word=text, start=start, end=start+.2 if end is None else end,
                           probability=probability)


def test_rejected_word_preserves_source_observation_and_splits_anchor():
    decoded = decode([word('قل', 0), word('هو', .3), word('سيارة', .6, .4),
                      word('الله', .9), word('أحد', 1.2)])
    assert [w['run_index'] for w in decoded['words']] == [0, 0, 1, 1]
    assert [w['text'] for w in decoded['observations']] == ['قل','هو','سيارة','الله','أحد']
    assert decoded['observations'][2]['recognition_state'] == 'unassessable'
    assert decoded['observations'][2]['confidence'] == .4
    corpus = Corpus(Path(__file__).resolve().parents[3])
    engine = SessionIntelligence(corpus, 'policy-fixture', 'test')
    row = {'decoded_state':{'evidence':[], 'verse':None, 'source':engine.source}, 'event_id':0}
    state, reply, _ = engine.process('test', row,
        AudioHeader(sequence=0,start_frame=16000,end_frame=80000), decoded)
    assert not state['evidence'], 'Two disjoint two-word fragments cannot become a four-word anchor'
    assert not any(e['type'] == 'WORD_CONFIRMED' for e in reply['events'])
    assert reply['observations'][2]['start'] == 1.6


def test_overlapping_or_reversed_backend_times_do_not_join_a_run():
    decoded = decode([word('قل', 0, end=.5), word('هو', .2), word('الله', .6), word('أحد', .9)])
    assert 'هو' not in [w['text'] for w in decoded['words']]
    assert decoded['words'][0]['run_index'] != decoded['words'][1]['run_index']
    assert decoded['unresolved'] is True


def test_nonfinite_backend_observation_is_retained_without_invalid_json_numbers():
    import json
    decoded = decode([word('قل', float('nan'), float('nan'))])
    assert not decoded['words'] and decoded['unresolved']
    observed = decoded['observations'][0]
    assert observed['start'] is None and observed['end'] is None and observed['confidence'] is None
    json.dumps(decoded, allow_nan=False)


def test_no_speech_segment_never_becomes_an_anchor_but_is_observable():
    decoded = decode([word('قل', 0), word('هو', .3), word('الله', .6), word('أحد', .9)], no_speech=.9)
    assert not decoded['words'] and decoded['unresolved']
    assert len(decoded['observations']) == 4
    assert all(w['recognition_state'] == 'unassessable' for w in decoded['observations'])


def test_segment_without_word_times_cannot_disappear_between_two_short_anchors():
    recognizer = Recognizer(Path('.'))
    class Model:
        def transcribe(self, samples, **options):
            return [SimpleNamespace(no_speech_prob=.01, text='قل هو', words=[word('قل', 0), word('هو', .3)]),
                    SimpleNamespace(no_speech_prob=.01, text='كلام غير واضح', words=None),
                    SimpleNamespace(no_speech_prob=.01, text='الله أحد', words=[word('الله', 1.5), word('أحد', 1.8)])], None
    recognizer.model = Model()
    decoded = recognizer._decode(np.tile(np.array([.06, -.06], dtype=np.float32), 32000))
    assert decoded['unresolved'] is True
    assert decoded['words'][1]['run_index'] != decoded['words'][2]['run_index']
    missing = decoded['observations'][2]
    assert missing['text'] == 'كلام غير واضح' and missing['recognition_state'] == 'unassessable'
    assert missing['start'] is None and missing['end'] is None and missing['confidence'] is None
