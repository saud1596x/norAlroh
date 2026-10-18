"""Synthetic path/clock policy tests only, never real-acoustic acceptance."""
import numpy as np
import pytest
from quran_onnx import collapse_words


def emissions(labels):
    matrix = np.full((len(labels), 5), -20., dtype=np.float32)
    for frame, label in enumerate(labels):
        matrix[frame, label] = 0
    return matrix


VOCAB = {'<pad>': 0, '|': 1, 'ق': 2, 'ل': 3, 'ه': 4}


def test_ctc_repeats_and_blank_are_actual_occurrences_not_canonical_words():
    words = collapse_words(emissions([2, 2, 0, 2, 3, 1, 1, 4]), VOCAB, 16000)
    assert [w['text'] for w in words] == ['ققل', 'ه']
    assert words[0]['start'] == 0 and words[0]['end'] == .1
    assert words[1]['start'] == .14 and words[1]['end'] == .16
    assert all(w['recognition_state'] == 'unvalidated-independent-hypothesis' for w in words)


def test_blank_or_delimiters_cannot_invent_a_word():
    assert collapse_words(emissions([0, 1, 0, 1]), VOCAB, 16000) == []


def test_source_clock_cannot_exceed_original_pcm():
    with pytest.raises(ValueError):
        collapse_words(emissions([0]*100+[2]), VOCAB, 16000)


def test_nonfinite_output_is_rejected():
    values = emissions([2, 3]); values[0, 0] = np.nan
    with pytest.raises(ValueError):
        collapse_words(values, VOCAB, 16000)
