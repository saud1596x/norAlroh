"""Exact input-clock diagnostics, not generated learner acoustic acceptance."""
import numpy as np
from evaluate_learner_pilot import windows


def test_overlapping_capture_windows_cover_exact_partial_tail_without_retiming_or_shared_mutation():
    original = np.arange(153_017, dtype=np.float32)/1_000_000
    before = original.copy()
    actual = list(windows(original))
    assert actual[0][:2] == (0, 32_000)
    assert actual[-1][:2] == (25_017, 153_017)
    assert all(end-start <= 128_000 and len(pcm) == end-start for start, end, pcm in actual)
    assert all(0 < right[1]-left[1] <= 16_000 for left, right in zip(actual, actual[1:]))
    for start, end, pcm in actual:
        assert np.array_equal(pcm, original[start:end])
        pcm[:] = 0
    assert np.array_equal(original, before), 'Inference working arrays cannot mutate original PCM'


def test_short_final_capture_is_not_padded_truncated_or_given_an_earlier_clock():
    original = np.array([0.012, -0.004, 0.03]*1001, dtype=np.float32)
    actual = list(windows(original))
    assert len(actual) == 1
    start, end, pcm = actual[0]
    assert (start, end) == (0, len(original))
    assert np.array_equal(pcm, original)
