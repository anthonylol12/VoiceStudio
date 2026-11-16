"""Streaming segmenter for live transcription.

Audio arrives as PCM16 mono 16 kHz chunks. Utterances are cut at pauses
(energy-based VAD) or after a maximum length, then transcribed while the
user keeps talking. Each cut keeps its absolute offset so text stays linked
to the position in the saved recording.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from .audio import SAMPLE_RATE, pcm16_to_float

FRAME_MS = 30
FRAME = SAMPLE_RATE * FRAME_MS // 1000


@dataclass
class Utterance:
    start_ms: int
    samples: np.ndarray

    @property
    def end_ms(self) -> int:
        return self.start_ms + int(len(self.samples) / SAMPLE_RATE * 1000)


class LiveSegmenter:
    """Adaptive energy VAD.

    A fixed threshold failed with a real Windows microphone picking up quiet
    speech (mean −50 dBFS, peaks −24 dBFS): word onsets and tails fell below
    it and were dropped. The threshold now follows the measured noise floor
    (start = ratio × noise), with hysteresis (stay voiced down to half of it)
    and 500 ms of pre-roll so the beginning of a phrase is kept.
    """

    def __init__(self, silence_ms: int = 700, min_ms: int = 1200, max_ms: int = 12000,
                 min_threshold: float = 0.0025, ratio: float = 3.0, preroll_ms: int = 500):
        self.silence_frames = silence_ms // FRAME_MS
        self.min_samples = SAMPLE_RATE * min_ms // 1000
        self.max_samples = SAMPLE_RATE * max_ms // 1000
        self.min_threshold = min_threshold
        self.ratio = ratio
        self.preroll = SAMPLE_RATE * preroll_ms // 1000
        self.noise = min_threshold / ratio  # running noise-floor estimate (RMS)
        self._pending = b""
        self._buf: list[np.ndarray] = []
        self._buf_len = 0
        self._buf_start = 0  # absolute sample index of buffer start
        self._consumed = 0  # absolute samples received
        self._silent = 0
        self._voiced = False
        self.all_audio: list[np.ndarray] = []

    @property
    def total_ms(self) -> int:
        return int(self._consumed / SAMPLE_RATE * 1000)

    def feed(self, data: bytes) -> list[Utterance]:
        data = self._pending + data
        usable = len(data) - (len(data) % 2)
        self._pending = data[usable:]
        samples = pcm16_to_float(data[:usable])
        self.all_audio.append(samples)
        out: list[Utterance] = []
        for i in range(0, len(samples), FRAME):
            frame = samples[i:i + FRAME]
            if self._buf_len == 0:
                self._buf_start = self._consumed
            self._consumed += len(frame)
            energy = float(np.sqrt(np.mean(frame ** 2))) if frame.size else 0.0
            start_level = max(self.min_threshold, self.noise * self.ratio)
            keep_level = start_level * 0.5  # hysteresis while inside speech
            if energy >= (keep_level if self._voiced else start_level):
                self._voiced = True
                self._silent = 0
            else:
                self._silent += 1
                # Learn the noise floor only from non-speech frames; adapt
                # down quickly and up slowly so speech does not raise it.
                rate = 0.2 if energy < self.noise else 0.02
                self.noise += (energy - self.noise) * rate
            if not self._voiced:
                # Drop leading silence but keep some pre-roll for word onsets.
                self._buf.append(frame)
                self._buf_len += len(frame)
                while self._buf_len > self.preroll and len(self._buf) > 1:
                    dropped = self._buf.pop(0)
                    self._buf_len -= len(dropped)
                    self._buf_start += len(dropped)
                continue
            self._buf.append(frame)
            self._buf_len += len(frame)
            pause = self._silent >= self.silence_frames and self._buf_len >= self.min_samples
            if pause or self._buf_len >= self.max_samples:
                out.append(self._cut())
        return out

    def _cut(self) -> Utterance:
        u = Utterance(int(self._buf_start / SAMPLE_RATE * 1000), np.concatenate(self._buf))
        self._buf, self._buf_len, self._silent, self._voiced = [], 0, 0, False
        return u

    def flush(self) -> Utterance | None:
        if self._buf_len == 0 or not self._voiced:
            self._buf, self._buf_len = [], 0
            return None
        return self._cut()

    def full_audio(self) -> np.ndarray:
        return np.concatenate(self.all_audio) if self.all_audio else np.zeros(0, dtype=np.float32)
