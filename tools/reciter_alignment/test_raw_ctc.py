"""Synthetic path/clock policy tests only, never real-acoustic acceptance."""
import numpy as np
import pytest
from quran_onnx import collapse_words, acoustic_windows, acoustic_logits, InferenceWorkDeadline, inference_identity


def emissions(labels):
    matrix = np.full((len(labels), 5), -20., dtype=np.float32)
    for frame, label in enumerate(labels):
        matrix[frame, label] = 0
    return matrix


VOCAB = {'<pad>': 0, '|': 1, 'ق': 2, 'ل': 3, 'ه': 4}


def test_inference_identity_keeps_precision_and_experimental_context_distinct():
    assert inference_identity('float32', 'whole') != inference_identity('float16', 'whole')
    assert inference_identity('float32', 'whole') != inference_identity('float32', 'experimental-context-stitch1')
    with pytest.raises(ValueError):
        inference_identity('automatic', 'whole')
    with pytest.raises(ValueError):
        inference_identity('float32', 'automatic')


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


def test_context_windows_keep_every_real_frame_once_on_original_clock_without_padding():
    for samples in (400, 16000, 480000, 480001, 960001, 1920000):
        windows = acoustic_windows(samples)
        covered = []
        for start, end, first, last, crop_start, crop_end in windows:
            assert 0 <= first < last <= samples
            assert last-first <= 480000
            assert first % 320 == 0
            assert crop_end-crop_start == end-start
            covered.extend(range(start, end))
        assert covered == list(range((samples-400)//320+1))
    # Generated ramp marks source indices only; this is not model/audio proof.
    values = np.arange(960001, dtype=np.float32)
    def marked_frames(chunk):
        return (chunk[0]/320+np.arange((len(chunk)-400)//320+1))[:, None]
    result = acoustic_logits(values, marked_frames)
    assert np.array_equal(result[:, 0], np.arange((len(values)-400)//320+1))


def test_acoustic_chunk_work_deadline_cannot_become_rejected_recitation_or_fake_frames():
    with pytest.raises(InferenceWorkDeadline):
        acoustic_logits(np.zeros(960001), lambda _: pytest.fail('No decoder after deadline'), deadline=0)
    with pytest.raises(ValueError):
        acoustic_logits(np.zeros(960001), lambda _: np.zeros((1, 2)))
