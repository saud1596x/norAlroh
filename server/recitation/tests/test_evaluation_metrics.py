"""Metric arithmetic fixtures, not generated speech or ASR quality evidence."""
import pytest

jiwer = pytest.importorskip('jiwer', reason='Offline evaluator dependency, never a production ASR requirement')
from evaluation_metrics import measure


def test_word_omission_substitution_and_repetition_are_not_hidden_in_one_score():
    omitted = measure(['قل','هو','الله','أحد'], ['قل','هو','أحد'])
    assert omitted['deletions'] == 1 and omitted['word_error_rate'] == .25
    changed = measure(['قل','هو','الله','أحد'], ['قل','هو','سيارة','أحد'])
    assert changed['substitutions'] == 1 and changed['deletions'] == 0
    repeated = measure(['الله','الصمد'], ['الله','الله','الصمد'])
    assert repeated['insertions'] == 1


def test_silence_and_full_abstention_keep_distinct_counts():
    assert measure([], [])['word_error_rate'] == 0
    assert measure([], ['قل','هو'])['silent_control_insertions'] == 2
    assert measure(['قل','هو'], [])['deletions'] == 2


def test_metrics_do_not_silently_tokenize_or_repair_model_words():
    for invalid in (['قل هو'], [''], [None]):
        with pytest.raises(ValueError):measure(['قل','هو'], invalid)
