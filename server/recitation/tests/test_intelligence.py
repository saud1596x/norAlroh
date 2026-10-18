import asyncio
from pathlib import Path
import time
import pytest
import numpy as np
from noor_engine.corpus import Corpus, normalize
from noor_engine.observations import candidates
from noor_engine.protocol import SessionIntelligence, AudioHeader
from noor_engine.inference import Recognizer, Busy, InferenceDeadline

ROOT = Path(__file__).resolve().parents[3]


@pytest.fixture(scope='module')
def corpus(): return Corpus(ROOT)


def heard_words(corpus, verse):
    words = [w for w in corpus.words if w.verse == verse]
    return [{'text':w.aliases[0][0], 'start':i*.3, 'end':i*.3+.2, 'confidence':.99}
            for i,w in enumerate(words) if len(w.aliases[0]) == 1]


def test_whole_corpus_anchors_ambiguity_and_cross_surah(corpus):
    for verse in ['112:1', '114:1', '19:4', '2:255']:
        heard = heard_words(corpus, verse)
        aligned = corpus.align(heard)
        assert aligned and all(v['verse'] == verse for v in aligned)
    # Shared phrase alone cannot choose one of the many basmalas/occurrences.
    assert corpus.align([{'text':w,'start':i*.2,'end':i*.2+.1,'confidence':.99}
                         for i,w in enumerate(['بسم','الله','الرحمن','الرحيم'])]) == []
    assert corpus.align([{'text':'سيارة','start':0,'end':1,'confidence':.99}]) == []


def test_short_verse_needs_a_prior_real_anchor_and_never_a_visible_page_hint(corpus):
    heard = heard_words(corpus, '112:2')
    assert not corpus.align(heard)
    first = next(i for i,w in enumerate(corpus.words) if w.verse == '112:2')
    aligned = corpus.align(heard, expected_cursor=first)
    assert aligned and all(w['verse'] == '112:2' for w in aligned)
    # The next few corpus words contain Falaq's shared opening too. Spatial
    # proximity alone cannot choose it before the distinctive word is heard.
    partial = heard_words(corpus, '114:1')[:2]
    assert not corpus.align(partial, expected_cursor=first)


def test_high_confidence_substitution_is_provisional_and_pause_not_error(corpus):
    heard = heard_words(corpus, '2:255')
    heard[8]['text'] = 'سيارة'
    aligned = corpus.align(heard)
    notes = candidates(corpus, heard, aligned)
    assert any(n['category'] == 'possible_substitution' for n in notes)
    assert all(not n['is_confirmed_recitation_error'] for n in notes)
    heard[8]['confidence'] = .8
    assert not candidates(corpus, heard, corpus.align(heard))
    heard[8]['confidence'] = .99
    for w in heard[9:]: w['start'] += 3; w['end'] += 3
    assert not candidates(corpus, heard, corpus.align(heard))


def test_independent_surah_anchors_survive_shared_cross_boundary_suffix(corpus):
    heard = heard_words(corpus,'112:1') + [dict(w,start=w['start']+2,end=w['end']+2) for w in heard_words(corpus,'114:1')]
    aligned = corpus.align(heard)
    assert [(v['verse'],v['position']) for v in aligned] == [('112:1',p) for p in range(1,5)] + [('114:1',p) for p in range(1,5)]


def test_revised_window_retracts_candidates_and_does_not_reveal_missing_word(corpus):
    engine = SessionIntelligence(corpus, 'test-model', 'test-revision')
    heard = heard_words(corpus, '2:255')[:30]
    original = [dict(w) for w in heard]; heard[8]['text'] = 'سيارة'
    header = AudioHeader(sequence=0, start_frame=0, end_frame=128000)
    # Keep the fault fixture within a real eight-second bounded window.
    heard = [w for w in heard if w['end'] <= 8]; original = [w for w in original if w['end'] <= 8]
    row = {'decoded_state':{'evidence':[], 'verse':None, 'source':engine.source}, 'event_id':0}
    state, result, count = engine.process('test-session', row, header, {'words':heard,'unresolved':False,'inference_ms':0})
    assert any(e['type']=='ERROR_CANDIDATE' for e in result['events'])
    assert not any(e['type']=='ERROR_CONFIRMED' for e in result['events'])
    missing = [w for w in corpus.words if w.verse == '2:255'][8].native_id
    assert missing not in [w['native_id'] for w in state['evidence']]
    row = {'decoded_state':state, 'event_id':count}
    _, revised, _ = engine.process('test-session', row, header, {'words':original,'unresolved':False,'inference_ms':0})
    assert any(e['type']=='ERROR_RETRACTED' for e in revised['events'])
    with pytest.raises(ValueError):
        engine.process('test-session', {'decoded_state':dict(state, source={'corpus_version':'wrong'}), 'event_id':count},
                       header, {'words':original,'unresolved':False,'inference_ms':0})


def test_timeout_retains_actual_compute_lease_until_decoder_returns(tmp_path):
    async def scenario():
        from threading import Event
        release = Event()
        recognizer = Recognizer(tmp_path, timeout=.01)
        recognizer.model = object()
        def slow(samples):
            release.wait(5)
            return {'words':[], 'unresolved':False, 'inference_ms':100}
        recognizer._decode = slow
        try:
            with pytest.raises(InferenceDeadline): await recognizer.recognize(np.zeros(1000))
            assert recognizer.healthy is False
            with pytest.raises(Busy): await recognizer.recognize(np.zeros(1000))
            pending = recognizer.pending
        finally: release.set()
        await asyncio.shield(pending)
        await asyncio.sleep(0)
        assert recognizer.pending is None and not recognizer.gate.locked()
        assert recognizer.healthy is True
    asyncio.run(scenario())
