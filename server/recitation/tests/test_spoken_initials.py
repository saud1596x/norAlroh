"""Lexical binding policy only. Injected tokens are not acoustic acceptance."""
from pathlib import Path
import pytest
from noor_engine.corpus import Corpus
from noor_engine.initials import OPENINGS, forms


def heard(tokens):
    return [dict(text=text, start=i, end=i+.8, confidence=.99) for i,text in enumerate(tokens)]


def test_complete_initial_names_preserve_positions_and_reject_incomplete_or_reordered_names():
    corpus = Corpus(Path(__file__).resolve().parents[3])
    assert len(OPENINGS) == 30
    for verse, canonical in OPENINGS.items():
        first = next(w for w in corpus.words if w.verse == verse and w.position == 1)
        assert (canonical,) in first.aliases
        assert forms(verse,1,(canonical,)).issubset(set(first.aliases))
    initial = next(w for w in corpus.words if w.verse == '2:1')
    assert ('الف','لام','ميم') in initial.aliases
    assert ('الفلام','ميم') in initial.aliases
    assert ('الف','ميم') not in initial.aliases
    assert ('ميم','لام','الف') not in initial.aliases
    assert not corpus.align(heard(['ألف','لام','ميم']))  # six shared openings, no page bias
    actual = heard(['ألف','لام','ميم','ذلك','الكتاب','لا','ريب','فيه'])
    bound = corpus.align(actual)
    assert bound and all(w['verse'] in ('2:1','2:2') for w in bound)
    opening = next(w for w in bound if w['verse'] == '2:1')
    assert opening['native_id'] == initial.native_id
    assert opening['start'] == 0 and opening['end'] == 2.8
    assert [x['text'] for x in actual][:3] == ['ألف','لام','ميم']


def test_initial_aliases_cannot_be_applied_to_other_words_or_modified_reference():
    assert forms('36:31',1,('الم',)) == set()
    assert forms('2:1',2,('الم',)) == set()
    with pytest.raises(ValueError):
        forms('2:1',1,('الر',))
    corpus = Corpus(Path(__file__).resolve().parents[3])
    ordinary = next(w for w in corpus.words if w.verse == '36:31' and w.position == 1)
    assert ('الف','لام','ميم') not in ordinary.aliases
