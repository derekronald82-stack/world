from pathlib import Path
from tempfile import TemporaryDirectory
from uuid import uuid4
import numpy as np
from pydub import AudioSegment
from .effects_8d import EffectParams, apply_8d_effect
from .normalizer import normalize_peak
from .storage import materialize_for_processing, store_generated_file


def _to_float_mono(seg: AudioSegment) -> tuple[np.ndarray, int]:
    seg = seg.set_frame_rate(44100).set_channels(1)
    samples = np.array(seg.get_array_of_samples()).astype(np.float32)
    max_int = float(1 << (8 * seg.sample_width - 1))
    if max_int <= 0:
        max_int = 32768.0
    return samples / max_int, seg.frame_rate


def convert_to_8d(
    input_relative: str,
    pan_speed: float = 0.5,
    intensity: float = 1.0,
    reverb: float = 0.35,
    decay: float = 2.5,
    output_prefix: str = "users/generated/eightd",
) -> str:
    """Create a stereo MP3 with circular HRTF-style panning + hall reverb.

    The processing engine is adapted from the user-provided 8D converter project.
    The source file may live on local storage or an S3-compatible bucket.
    """
    with materialize_for_processing(input_relative) as source:
        seg = AudioSegment.from_file(source)
        mono, sr = _to_float_mono(seg)

    params = EffectParams(
        pan_speed_hz=pan_speed,
        reverb_wet=reverb,
        reverb_decay_sec=decay,
        intensity=intensity,
    )
    stereo = apply_8d_effect(mono, sr, params)
    stereo = normalize_peak(stereo, target_dbfs=-1.0)

    pcm = np.clip(stereo * 32767.0, -32768, 32767).astype(np.int16)
    rendered = AudioSegment(pcm.tobytes(), frame_rate=sr, sample_width=2, channels=2)

    relative = (Path(output_prefix) / f"{uuid4().hex}_8d.mp3").as_posix()
    with TemporaryDirectory(prefix="catws-ffmpeg-") as temp_dir:
        output_path = Path(temp_dir) / "rendered.mp3"
        rendered.export(str(output_path), format="mp3", bitrate="192k")
        return store_generated_file(output_path, relative)
