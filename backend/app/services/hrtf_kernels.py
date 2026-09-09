"""
hrtf_kernels.py - Lightweight, synthetic HRTF-style impulse responses.

Full measured HRTF databases (SOFA format, e.g. CIPIC/MIT KEMAR) require
downloading large binary files, which breaks the "works offline after
one-command setup" requirement. Instead, this module synthesizes small
left/right impulse responses that approximate the two dominant perceptual
cues of a real HRTF for a given azimuth angle:

1. ITD (Interaural Time Difference) - a sub-sample delay between ears,
   modeled with a fractional-delay (sinc) filter, based on a simple
   spherical-head model.
2. ILD / pinna shading (Interaural Level Difference) - a one-pole shelf
   filter that attenuates high frequencies on the ear facing away from
   the sound source, approximating head shadow + outer-ear filtering.

This is NOT a substitute for a measured HRTF, but combined with the
circular panning LFO and reverb in effects.py it produces a convincing,
fully-offline 8D binaural effect using only numpy/scipy.
"""

from __future__ import annotations

import functools
from typing import Tuple

import numpy as np
from scipy import signal

HEAD_RADIUS_M = 0.0875  # average adult head radius, meters
SPEED_OF_SOUND = 343.0  # m/s
KERNEL_LENGTH = 64  # taps; short enough to be fast, long enough for fractional delay


def _fractional_delay_kernel(delay_samples: float, length: int = KERNEL_LENGTH) -> np.ndarray:
    """
    Build a windowed-sinc FIR filter that delays a signal by a fractional
    number of samples (can be negative for an advance/lead).
    """
    n = np.arange(length) - length // 2
    h = np.sinc(n - delay_samples)
    window = np.hamming(length)
    h *= window
    total = np.sum(h)
    if abs(total) > 1e-8:
        h /= total
    return h.astype(np.float32)


def _itd_seconds(azimuth_rad: float) -> float:
    """
    Woodworth's formula: interaural time difference for a spherical head.
    azimuth: 0 = front, +pi/2 = right, -pi/2 = left (radians).
    """
    return (HEAD_RADIUS_M / SPEED_OF_SOUND) * (azimuth_rad + np.sin(azimuth_rad))


def _shelf_coefficient(azimuth_rad: float, ear: str) -> float:
    """
    Approximate head-shadow attenuation (0..1 gain multiplier for high
    frequencies) for the given ear at a given azimuth. The ear facing
    away from the source gets more high-frequency attenuation.
    """
    # cos term: +1 when source is directly on this ear's side, -1 opposite
    side_sign = 1.0 if ear == "right" else -1.0
    facing = np.cos(azimuth_rad - side_sign * (np.pi / 2))
    # Map facing (-1..1) to attenuation gain (0.35..1.0)
    gain = 0.675 + 0.325 * facing
    return float(np.clip(gain, 0.35, 1.0))


@functools.lru_cache(maxsize=720)
def get_hrtf_pair(azimuth_degrees: float, sr: int = 44100) -> Tuple[np.ndarray, np.ndarray]:
    """
    Generate a (left_ir, right_ir) pair of short FIR impulse responses that
    approximate the HRTF for a sound source at the given azimuth.

    Args:
        azimuth_degrees: 0 = front, 90 = full right, -90/270 = full left,
            180 = behind. Full 360-degree circular range supported.
        sr: Sample rate, used to convert ITD seconds -> ITD samples.

    Returns:
        (left_ir, right_ir): two 1D float32 numpy arrays of equal length.
    """
    azimuth_rad = np.deg2rad(azimuth_degrees % 360.0)

    itd_sec = _itd_seconds(azimuth_rad)
    itd_samples = itd_sec * sr

    # Split the total ITD symmetrically: one ear leads, the other lags.
    left_delay = -itd_samples / 2.0
    right_delay = itd_samples / 2.0

    left_ir = _fractional_delay_kernel(left_delay)
    right_ir = _fractional_delay_kernel(right_delay)

    # Apply a simple one-pole low-pass "shelf" to simulate head shadow,
    # scaled by per-ear gain derived from azimuth.
    left_gain = _shelf_coefficient(azimuth_rad, "left")
    right_gain = _shelf_coefficient(azimuth_rad, "right")

    # One-pole lowpass: y[n] = a*x[n] + (1-a)*y[n-1]; lower gain -> more smoothing
    b_left, a_left = [1 - left_gain * 0.5], [1, -(left_gain * 0.5)]
    b_right, a_right = [1 - right_gain * 0.5], [1, -(right_gain * 0.5)]

    left_ir = signal.lfilter(b_left, a_left, left_ir).astype(np.float32)
    right_ir = signal.lfilter(b_right, a_right, right_ir).astype(np.float32)

    return left_ir, right_ir
