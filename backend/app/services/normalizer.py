"""
normalizer.py - Loudness / peak normalization utilities.

Provides simple, dependency-light normalization so exported files hit a
consistent, safe peak level (default target: -1 dBFS) without clipping.
"""

from __future__ import annotations

import logging

import numpy as np

logger = logging.getLogger(__name__)


def _db_to_linear(db: float) -> float:
    return float(10.0 ** (db / 20.0))


def normalize_peak(audio: np.ndarray, target_dbfs: float = -1.0) -> np.ndarray:
    """
    Normalize a (mono or multi-channel) audio array so its absolute peak
    sample hits `target_dbfs` decibels relative to full scale.

    Args:
        audio: numpy array, any shape, float samples (roughly -1..1 range).
        target_dbfs: Desired peak level in dBFS (e.g. -1.0 for -1 dBFS).

    Returns:
        Normalized float32 array, same shape as input. Silent input is
        returned unchanged (avoids divide-by-zero / noise amplification).
    """
    peak = np.max(np.abs(audio)) if audio.size else 0.0

    if peak < 1e-9:
        logger.warning("Audio is silent or near-silent; skipping normalization.")
        return audio.astype(np.float32)

    target_linear = _db_to_linear(target_dbfs)
    gain = target_linear / peak
    normalized = audio * gain

    # Hard safety clip in case of any floating point overshoot.
    normalized = np.clip(normalized, -1.0, 1.0)

    logger.info(
        "Normalized audio: peak %.2f dBFS -> %.2f dBFS (gain x%.3f)",
        20 * np.log10(peak + 1e-12),
        target_dbfs,
        gain,
    )
    return normalized.astype(np.float32)


def normalize_lufs_approx(audio: np.ndarray, target_rms_dbfs: float = -20.0) -> np.ndarray:
    """
    Approximate loudness normalization via RMS matching (a lightweight
    stand-in for full ITU-R BS.1770 LUFS metering, which would require an
    extra dependency such as pyloudnorm).

    Args:
        audio: numpy array of float samples.
        target_rms_dbfs: Desired RMS level in dBFS.

    Returns:
        Gain-adjusted float32 array, safety-clipped to [-1, 1].
    """
    rms = np.sqrt(np.mean(np.square(audio))) if audio.size else 0.0
    if rms < 1e-9:
        return audio.astype(np.float32)

    target_linear = _db_to_linear(target_rms_dbfs)
    gain = target_linear / rms
    adjusted = np.clip(audio * gain, -1.0, 1.0)
    return adjusted.astype(np.float32)
