"""
effects.py - 8D audio processing engine.

Pipeline (mono input -> stereo output):
    1. Circular panning: a slow sine/cosine LFO (0.3-0.7 Hz) drives a
       simulated azimuth angle that sweeps 360 degrees around the listener.
    2. HRTF-style binaural filtering: at each processing block, the current
       azimuth selects a pair of short synthetic HRTF impulse responses
       (utils.hrtf_kernels) which are convolved with the block to produce
       left/right channels with realistic ITD + head-shadow cues.
    3. Hall reverb: a Schroeder-style reverb (parallel comb filters +
       series all-pass filters) with a 2-3s decay tail, mixed in at a
       configurable wet ratio.
    4. Peak normalization to a safe target (handled by utils.normalizer,
       called from exporter.py after this module runs).

Performance: processing is done in overlapping blocks with per-block HRTF
convolution (not per-sample), which keeps a 3-4 minute song well under the
30-second processing budget on an average laptop.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass

import numpy as np
from scipy import signal

from .hrtf_kernels import get_hrtf_pair

logger = logging.getLogger(__name__)


@dataclass
class EffectParams:
    """User-tunable parameters for the 8D effect."""

    pan_speed_hz: float = 0.5      # LFO frequency, clamped to [0.3, 0.7] Hz
    reverb_wet: float = 0.35       # wet mix ratio, clamped to [0.30, 0.40]
    reverb_decay_sec: float = 2.5  # decay tail length, clamped to [2.0, 3.0]
    intensity: float = 1.0         # 0.0 (subtle) .. 1.0 (full) .. 1.5 (exaggerated)

    def clamped(self) -> "EffectParams":
        """Return a copy with all parameters clamped to safe/sane ranges."""
        return EffectParams(
            pan_speed_hz=float(np.clip(self.pan_speed_hz, 0.3, 0.7)),
            reverb_wet=float(np.clip(self.reverb_wet, 0.30, 0.40)),
            reverb_decay_sec=float(np.clip(self.reverb_decay_sec, 2.0, 3.0)),
            intensity=float(np.clip(self.intensity, 0.0, 1.5)),
        )


# --------------------------------------------------------------------------
# Circular panning + HRTF binaural rendering
# --------------------------------------------------------------------------

_BLOCK_SIZE = 2048  # samples per HRTF-convolution block


def _equal_power_pan_gains(azimuth_rad: float, intensity: float) -> tuple[float, float]:
    """
    Compute strong, clearly-audible equal-power left/right amplitude gains
    for the current azimuth. This is layered on top of the subtler HRTF
    spectral/ITD cues from get_hrtf_pair() so the classic "8D" circular
    motion is unmistakable, not just theoretically present.

    Args:
        azimuth_rad: current azimuth in radians (0=front, pi/2=right, etc).
        intensity: 0..1.5, scales how hard the pan swings between ears.
            At 0.0 the source stays centered; at 1.0 it swings fully
            hard-left/hard-right at the sides of the circle.

    Returns:
        (left_gain, right_gain) linear amplitude multipliers.
    """
    # x in [-1, 1]: the left-right component of the circular position.
    # sin() is 0 at front/back (0 deg, 180 deg) and +/-1 at the sides.
    x = np.sin(azimuth_rad)
    x = float(np.clip(x * min(intensity, 1.0), -1.0, 1.0))

    theta = (x + 1.0) * (np.pi / 4.0)  # maps [-1,1] -> [0, pi/2]
    left_gain = float(np.cos(theta))
    right_gain = float(np.sin(theta))

    # Above intensity=1.0, exaggerate further toward a harder, more
    # aggressive pan than pure equal-power (clamped to avoid full silence).
    if intensity > 1.0:
        extra = min(intensity - 1.0, 0.5) / 0.5  # 0..1
        left_gain = left_gain * (1 - 0.4 * extra) if x > 0 else min(1.0, left_gain * (1 + 0.4 * extra))
        right_gain = right_gain * (1 - 0.4 * extra) if x < 0 else min(1.0, right_gain * (1 + 0.4 * extra))

    return left_gain, right_gain


def _binaural_pan(mono: np.ndarray, sr: int, params: EffectParams,
                   progress_cb=None) -> np.ndarray:
    """
    Render a mono signal into stereo using a circularly-panned HRTF.

    Args:
        mono: 1D float32 mono audio.
        sr: sample rate.
        params: effect parameters (already clamped).
        progress_cb: optional callable(fraction: float) for progress updates.

    Returns:
        (N, 2) float32 stereo array.
    """
    n_samples = len(mono)
    n_blocks = int(np.ceil(n_samples / _BLOCK_SIZE))

    out_left = np.zeros(n_samples + 128, dtype=np.float32)  # pad for conv tails
    out_right = np.zeros(n_samples + 128, dtype=np.float32)

    two_pi_f_over_sr = 2 * np.pi * params.pan_speed_hz / sr

    for block_idx in range(n_blocks):
        start = block_idx * _BLOCK_SIZE
        end = min(start + _BLOCK_SIZE, n_samples)
        block = mono[start:end]
        if len(block) == 0:
            continue

        # Azimuth at the center of this block, from a slow sine LFO mapped
        # to a full 360-degree circular sweep.
        center_sample = start + len(block) / 2.0
        phase = two_pi_f_over_sr * center_sample
        azimuth_deg = (np.sin(phase) * 180.0) % 360.0

        left_ir, right_ir = get_hrtf_pair(round(float(azimuth_deg), 1), sr=sr)

        # Blend intensity: at intensity=0 the panning collapses toward center
        # (mono-ish), at 1.0 full HRTF effect, above 1.0 slightly exaggerated
        # via a sharper IR (approximated by scaling IR contrast).
        if params.intensity != 1.0:
            mid = (left_ir + right_ir) / 2.0
            left_ir = mid + (left_ir - mid) * params.intensity
            right_ir = mid + (right_ir - mid) * params.intensity

        conv_l = signal.fftconvolve(block, left_ir, mode="full")
        conv_r = signal.fftconvolve(block, right_ir, mode="full")

        # Layer strong, clearly-audible equal-power amplitude panning on
        # top of the subtle HRTF spectral/ITD cues computed above.
        pan_l, pan_r = _equal_power_pan_gains(np.deg2rad(azimuth_deg), params.intensity)
        conv_l *= pan_l
        conv_r *= pan_r

        seg_len = len(conv_l)
        out_left[start:start + seg_len] += conv_l
        out_right[start:start + seg_len] += conv_r

        if progress_cb and n_blocks > 0:
            progress_cb(0.1 + 0.55 * (block_idx + 1) / n_blocks)

    out_left = out_left[:n_samples]
    out_right = out_right[:n_samples]
    stereo = np.stack([out_left, out_right], axis=-1).astype(np.float32)
    return stereo


# --------------------------------------------------------------------------
# Hall reverb (Schroeder: parallel combs + series allpasses)
# --------------------------------------------------------------------------

def _phase_decompose(x: np.ndarray, delay: int) -> np.ndarray:
    """
    Reshape a 1D signal into a 2D array of shape (num_periods, delay) such
    that column `p` holds the subsequence x[p], x[p+delay], x[p+2*delay], ...
    This lets a feedback-at-lag-`delay` recursive filter be computed as a
    single *first-order* IIR applied along axis=0 across all `delay`
    independent phases at once (vectorized in C by scipy), instead of one
    huge order-`delay` direct-form filter walked sample-by-sample.
    """
    n = len(x)
    n_periods = int(np.ceil(n / delay))
    padded_len = n_periods * delay
    x_padded = np.zeros(padded_len, dtype=np.float64)
    x_padded[:n] = x
    return x_padded.reshape(n_periods, delay)


def _fast_comb_filter(x: np.ndarray, delay: int, feedback: float) -> np.ndarray:
    """
    Feedback comb filter: y[n] = x[n - delay] + feedback * y[n - delay].

    Because the recursion only ever references samples `delay` steps back,
    the signal can be split into `delay` independent phase subsequences,
    each obeying a simple first-order recursion y_p[k] = x_p[k] + fb*y_p[k-1].
    All phases are solved in one vectorized scipy.signal.lfilter call
    (axis=0 over the 2D phase matrix), which is orders of magnitude faster
    than a single order-`delay` direct-form IIR for large delay values.
    """
    n = len(x)
    x64 = x.astype(np.float64)
    phased = _phase_decompose(x64, delay)
    filtered = signal.lfilter([1.0], [1.0, -feedback], phased, axis=0)
    y = filtered.reshape(-1)[:n]
    return y.astype(np.float32)


def _fast_allpass_filter(x: np.ndarray, delay: int, gain: float = 0.7) -> np.ndarray:
    """
    Schroeder all-pass filter: y[n] = -g*x[n] + x[n-delay] + g*y[n-delay].

    Per phase subsequence this reduces to a first-order IIR
    y_p[k] - g*y_p[k-1] = -g*x_p[k] + x_p[k-1], solved vectorized across
    all `delay` phases at once, same trick as `_fast_comb_filter`.
    """
    n = len(x)
    x64 = x.astype(np.float64)
    phased = _phase_decompose(x64, delay)
    filtered = signal.lfilter([-gain, 1.0], [1.0, -gain], phased, axis=0)
    y = filtered.reshape(-1)[:n]
    return y.astype(np.float32)


def _hall_reverb(stereo: np.ndarray, sr: int, params: EffectParams,
                  progress_cb=None) -> np.ndarray:
    """
    Apply a Schroeder-style hall reverb to a stereo signal.

    Uses 4 parallel comb filters + 2 series all-pass filters per channel,
    tuned so the overall decay (T60) approximates `params.reverb_decay_sec`.
    """
    decay = params.reverb_decay_sec

    # Classic Schroeder comb delays (ms), scaled slightly by decay length.
    comb_delays_ms = [29.7, 37.1, 41.1, 43.7]
    allpass_delays_ms = [5.0, 1.7]

    def feedback_for_delay(delay_ms: float) -> float:
        # Solve for feedback g such that g^(T60 / delay_time) = 0.001 (-60dB)
        delay_sec = delay_ms / 1000.0
        n_repeats = decay / delay_sec
        g = 0.001 ** (1.0 / max(n_repeats, 1.0))
        return float(np.clip(g, 0.0, 0.98))

    def process_channel(channel: np.ndarray) -> np.ndarray:
        comb_sum = np.zeros_like(channel, dtype=np.float32)
        for ms in comb_delays_ms:
            delay_samples = max(1, int(sr * ms / 1000.0))
            fb = feedback_for_delay(ms)
            comb_sum += _fast_comb_filter(channel, delay_samples, fb)
        comb_sum /= len(comb_delays_ms)

        wet = comb_sum
        for ms in allpass_delays_ms:
            delay_samples = max(1, int(sr * ms / 1000.0))
            wet = _fast_allpass_filter(wet, delay_samples, gain=0.7)
        return wet

    left_wet = process_channel(stereo[:, 0])
    if progress_cb:
        progress_cb(0.8)
    right_wet = process_channel(stereo[:, 1])
    if progress_cb:
        progress_cb(0.9)

    wet_stereo = np.stack([left_wet, right_wet], axis=-1)
    dry = params.reverb_wet
    mixed = stereo * (1.0 - dry) + wet_stereo * dry
    return mixed.astype(np.float32)


# --------------------------------------------------------------------------
# Public entry point
# --------------------------------------------------------------------------

def apply_8d_effect(
    mono: np.ndarray,
    sr: int,
    params: EffectParams | None = None,
    progress_cb=None,
) -> np.ndarray:
    """
    Apply the full 8D audio pipeline (circular HRTF panning + hall reverb)
    to a mono signal.

    Args:
        mono: 1D float32 mono audio samples.
        sr: sample rate in Hz.
        params: EffectParams controlling pan speed, reverb, and intensity.
            Values outside safe ranges are automatically clamped.
        progress_cb: optional callable(fraction: float in [0,1]) invoked
            periodically to report progress (for GUI/API progress bars).

    Returns:
        (N, 2) float32 stereo array, NOT yet normalized (caller should
        apply utils.normalizer.normalize_peak before export).
    """
    if params is None:
        params = EffectParams()
    params = params.clamped()

    if mono.ndim != 1:
        raise ValueError("apply_8d_effect expects a 1D mono array.")

    logger.info(
        "Applying 8D effect: pan_speed=%.2fHz reverb_wet=%.2f decay=%.2fs intensity=%.2f",
        params.pan_speed_hz, params.reverb_wet, params.reverb_decay_sec, params.intensity,
    )

    if progress_cb:
        progress_cb(0.05)

    stereo = _binaural_pan(mono, sr, params, progress_cb=progress_cb)

    if progress_cb:
        progress_cb(0.65)

    result = _hall_reverb(stereo, sr, params, progress_cb=progress_cb)

    if progress_cb:
        progress_cb(1.0)

    return result
