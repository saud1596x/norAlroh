"""Inference-copy conditioning; original PCM and its frame clock are immutable."""
import numpy as np


def condition(original):
    values = np.asarray(original, dtype=np.float32)
    if (values.ndim != 1 or not len(values) or not np.isfinite(values).all()
            or np.max(np.abs(values)) > 1):
        raise ValueError('Invalid normalized mono PCM')
    mean = float(values.astype(np.float64).mean())
    centered = values - np.float32(mean) if abs(mean) >= .01 else values.copy()
    peak = float(np.max(np.abs(centered)))
    if peak == 0:
        return centered
    rms = float(np.sqrt(np.mean(centered.astype(np.float64)**2)))
    gain = max(1, min(256, .06/max(rms, .000001), .9/peak))
    if peak > 1:
        gain = .99/peak
    return centered * np.float32(gain)
