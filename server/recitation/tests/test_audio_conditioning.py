"""Fault handling tests, not acoustic recognition/learner accuracy claims."""
import numpy as np
import pytest
from noor_engine.audio import condition


def test_dc_offset_does_not_consume_weak_speech_gain_or_change_original_clock():
    voice = (.001*np.sin(np.arange(16000)*.1)).astype(np.float32)
    original = voice + .15
    saved = original.copy()
    output = condition(original)
    assert np.array_equal(saved, original)
    assert output.shape == original.shape
    assert abs(float(output.mean())) < 1e-6
    assert np.sqrt(np.mean(output.astype(np.float64)**2)) == pytest.approx(.06)
    assert np.corrcoef(voice, output)[0, 1] > .999999


def test_constant_corrupted_signal_becomes_silence_not_speech_and_normal_audio_is_identical():
    assert np.count_nonzero(condition(np.full(16000, .15, dtype=np.float32))) == 0
    audible = np.tile(np.array([.95, -.95, .4, -.4], dtype=np.float32), 4000)
    assert np.array_equal(condition(audible), audible)
    assert np.max(np.abs(condition(np.r_[np.full(15999, .8), -1.]))) < 1


@pytest.mark.parametrize('values', [[], [[.1]], [np.nan], [np.inf], [1.1], [-1.01]])
def test_invalid_pcm_never_reaches_recognizer(values):
    with pytest.raises(ValueError):
        condition(values)
