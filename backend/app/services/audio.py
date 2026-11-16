"""Audio helpers built on FFmpeg: any input format -> 16 kHz mono PCM."""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

import numpy as np

from ..config import get_settings

SAMPLE_RATE = 16000
SUPPORTED_AUDIO = {".wav", ".mp3", ".m4a", ".aac", ".flac", ".ogg", ".opus", ".webm"}


class AudioError(RuntimeError):
    pass


def ffmpeg_path() -> str | None:
    return shutil.which(get_settings().ffmpeg_binary)


def load_audio(path: Path) -> np.ndarray:
    """Decodes [path] with FFmpeg into float32 mono samples at 16 kHz."""
    ff = ffmpeg_path()
    if ff is None:
        raise AudioError("FFmpeg no está instalado o no está en el PATH (VS_FFMPEG_BINARY).")
    cmd = [ff, "-nostdin", "-hide_banner", "-loglevel", "error", "-i", str(path),
           "-ac", "1", "-ar", str(SAMPLE_RATE), "-f", "s16le", "-"]
    proc = subprocess.run(cmd, capture_output=True, check=False)
    if proc.returncode != 0:
        raise AudioError(f"No se pudo decodificar el audio: {proc.stderr.decode(errors='ignore').strip()[:300]}")
    return pcm16_to_float(proc.stdout)


def pcm16_to_float(data: bytes) -> np.ndarray:
    return np.frombuffer(data, dtype=np.int16).astype(np.float32) / 32768.0


def rms(samples: np.ndarray) -> float:
    if samples.size == 0:
        return 0.0
    return float(np.sqrt(np.mean(np.square(samples))))
