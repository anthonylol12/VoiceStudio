"""Provider interfaces and implementations.

Every AI capability is behind a small interface so engines can be swapped
(local/offline vs. cloud, free vs. paid) without touching the API layer.
Heavy libraries are imported lazily: the server starts even when an engine
is not installed and reports it through /api/v1/engines.
"""

from __future__ import annotations

import importlib.util
import io
import threading
import wave
from dataclasses import dataclass, field
from pathlib import Path
from typing import Protocol

import numpy as np

from ..config import Settings
from .audio import SAMPLE_RATE


class EngineUnavailable(RuntimeError):
    """Raised when an engine is not installed/configured. Maps to HTTP 503."""


@dataclass
class EngineStatus:
    available: bool
    name: str
    detail: str

    def as_dict(self) -> dict:
        return {"available": self.available, "name": self.name, "detail": self.detail}


def _installed(module: str) -> bool:
    try:
        return importlib.util.find_spec(module) is not None
    except ModuleNotFoundError:  # parent package missing ("pyannote" for "pyannote.audio")
        return False


# --------------------------------------------------------------------------
# Speech recognition
# --------------------------------------------------------------------------


@dataclass
class Segment:
    start_ms: int
    end_ms: int
    text: str
    language: str | None = None
    speaker: str = "S1"

    def as_dict(self) -> dict:
        return {"start_ms": self.start_ms, "end_ms": self.end_ms, "text": self.text,
                "language": self.language, "speaker": self.speaker}


@dataclass
class Transcription:
    language: str | None
    duration_ms: int
    segments: list[Segment] = field(default_factory=list)


class TranscriptionProvider(Protocol):
    def status(self) -> EngineStatus: ...
    def transcribe(self, samples: np.ndarray, language: str | None = None) -> Transcription: ...


class FasterWhisperProvider:
    """Local Whisper (CTranslate2). Runs offline once the model is cached."""

    def __init__(self, settings: Settings):
        self.s = settings
        self._model = None
        self._lock = threading.Lock()

    def status(self) -> EngineStatus:
        if not _installed("faster_whisper"):
            return EngineStatus(False, "faster-whisper", "No instalado: pip install -r requirements-ai.txt")
        return EngineStatus(True, "faster-whisper", f"Modelo '{self.s.whisper_model}' ({'cargado' if self._model else 'se descarga/carga al primer uso'})")

    def _get(self):
        if self._model is None:
            with self._lock:
                if self._model is None:
                    if not _installed("faster_whisper"):
                        raise EngineUnavailable("faster-whisper no está instalado en el backend.")
                    from faster_whisper import WhisperModel

                    self._model = WhisperModel(self.s.whisper_model, device=self.device,
                                               compute_type=self.s.whisper_compute_type)
        return self._model

    device_override: str | None = None

    @property
    def device(self) -> str:
        return self.device_override or self.s.whisper_device

    @staticmethod
    def _is_gpu_runtime_error(e: Exception) -> bool:
        msg = str(e).lower()
        return any(k in msg for k in ("cublas", "cudnn", "cuda", "cufft"))

    def transcribe(self, samples: np.ndarray, language: str | None = None) -> Transcription:
        try:
            return self._transcribe(samples, language)
        except RuntimeError as e:
            # "auto" picks an NVIDIA GPU when one exists even if the CUDA
            # libraries are not installed; fall back to CPU once.
            if self.device == "cpu" or not self._is_gpu_runtime_error(e):
                raise
            import logging

            logging.getLogger("voicestudio").warning("GPU no utilizable (%s); se usa la CPU para Whisper.", e)
            with self._lock:
                self.device_override = "cpu"
                self._model = None
            return self._transcribe(samples, language)

    def _transcribe(self, samples: np.ndarray, language: str | None = None) -> Transcription:
        model = self._get()
        segments, info = model.transcribe(samples, language=language, vad_filter=True, beam_size=5,
                                          condition_on_previous_text=False)
        duration_ms = int(len(samples) / SAMPLE_RATE * 1000)
        # Whisper can report an end time past the end of the audio; clamp so
        # tap-to-seek and SRT export stay inside the recording.
        out = [Segment(min(int(s.start * 1000), duration_ms), min(int(s.end * 1000), duration_ms), s.text.strip(), info.language)
               for s in segments if s.text.strip()]
        # Mixed-language audio: re-detect language per segment when auto.
        if language is None and len(out) > 1:
            for seg in out:
                chunk = samples[int(seg.start_ms * SAMPLE_RATE / 1000): int(seg.end_ms * SAMPLE_RATE / 1000)]
                if chunk.size > SAMPLE_RATE:  # >1 s
                    try:
                        lang, prob, _ = model.detect_language(chunk)
                        if prob > 0.6:
                            seg.language = lang
                    except Exception:  # older faster-whisper without detect_language
                        break
        return Transcription(info.language, int(len(samples) / SAMPLE_RATE * 1000), out)


# --------------------------------------------------------------------------
# Speaker diarization
# --------------------------------------------------------------------------


@dataclass
class Turn:
    start_ms: int
    end_ms: int
    speaker: str


class DiarizationProvider(Protocol):
    def status(self) -> EngineStatus: ...
    def diarize(self, samples: np.ndarray) -> list[Turn]: ...


class PyannoteProvider:
    """pyannote.audio pipeline. Generic labels only (S1, S2…); no biometric
    identification of people is performed or stored."""

    def __init__(self, settings: Settings):
        self.s = settings
        self._pipeline = None
        self._lock = threading.Lock()

    def status(self) -> EngineStatus:
        if not _installed("pyannote.audio"):
            return EngineStatus(False, "pyannote.audio", "No instalado (opcional): pip install pyannote.audio")
        if not self.s.hf_token:
            return EngineStatus(False, "pyannote.audio", "Falta VS_HF_TOKEN (token de Hugging Face con acceso al modelo)")
        return EngineStatus(True, "pyannote.audio", self.s.diarization_model)

    def _get(self):
        st = self.status()
        if not st.available:
            raise EngineUnavailable(st.detail)
        if self._pipeline is None:
            with self._lock:
                if self._pipeline is None:
                    from pyannote.audio import Pipeline

                    self._pipeline = Pipeline.from_pretrained(self.s.diarization_model, token=self.s.hf_token)
        return self._pipeline

    def diarize(self, samples: np.ndarray) -> list[Turn]:
        pipeline = self._get()  # raises EngineUnavailable before touching torch
        import torch

        result = pipeline({"waveform": torch.from_numpy(samples).unsqueeze(0), "sample_rate": SAMPLE_RATE})
        annotation = getattr(result, "speaker_diarization", result)
        labels: dict[str, str] = {}
        turns = []
        for seg, _, label in annotation.itertracks(yield_label=True):
            key = labels.setdefault(label, f"S{len(labels) + 1}")
            turns.append(Turn(int(seg.start * 1000), int(seg.end * 1000), key))
        return turns


def assign_speakers(segments: list[Segment], turns: list[Turn]) -> list[Segment]:
    """Labels each transcript segment with the speaker whose turns overlap it
    the most. Speakers are renumbered by first appearance (S1, S2…)."""
    if not turns:
        return segments
    for seg in segments:
        best, best_overlap = None, 0
        for t in turns:
            overlap = min(seg.end_ms, t.end_ms) - max(seg.start_ms, t.start_ms)
            if overlap > best_overlap:
                best, best_overlap = t.speaker, overlap
        if best is None:  # no overlap: nearest turn
            best = min(turns, key=lambda t: min(abs(t.start_ms - seg.end_ms), abs(t.end_ms - seg.start_ms))).speaker
        seg.speaker = best
    order: dict[str, str] = {}
    for seg in segments:
        seg.speaker = order.setdefault(seg.speaker, f"S{len(order) + 1}")
    return segments


# --------------------------------------------------------------------------
# Text to speech
# --------------------------------------------------------------------------


class TtsProvider(Protocol):
    def status(self) -> EngineStatus: ...
    def voices(self) -> list[str]: ...
    def synthesize(self, text: str, language: str, voice: str = "") -> bytes: ...


class PiperProvider:
    """Piper neural TTS, fully local. Voices (.onnx + .onnx.json) live in
    VS_PIPER_VOICES_DIR; see documentation/ENGINES.md for download links."""

    def __init__(self, settings: Settings):
        self.s = settings
        self._voices: dict[str, object] = {}
        self._lock = threading.Lock()

    def voices(self) -> list[str]:
        return sorted(p.name.removesuffix(".onnx") for p in Path(self.s.piper_voices_dir).glob("*.onnx"))

    def status(self) -> EngineStatus:
        if not _installed("piper"):
            return EngineStatus(False, "Piper", "No instalado: pip install piper-tts")
        v = self.voices()
        if not v:
            return EngineStatus(False, "Piper", f"Sin voces en {self.s.piper_voices_dir}")
        return EngineStatus(True, "Piper", f"{len(v)} voz/voces: {', '.join(v)}")

    def _voice_name(self, language: str, voice: str) -> str:
        available = self.voices()
        if voice and voice in available:
            return voice
        default = self.s.piper_default_es if language.startswith("es") else self.s.piper_default_en
        if default in available:
            return default
        match = [v for v in available if v.lower().startswith(language[:2].lower())]
        if not match:
            raise EngineUnavailable(f"No hay voz Piper instalada para '{language}'.")
        return match[0]

    def synthesize(self, text: str, language: str, voice: str = "") -> bytes:
        st = self.status()
        if not st.available:
            raise EngineUnavailable(st.detail)
        name = self._voice_name(language, voice)
        with self._lock:
            if name not in self._voices:
                from piper import PiperVoice

                self._voices[name] = PiperVoice.load(str(Path(self.s.piper_voices_dir) / f"{name}.onnx"))
            pv = self._voices[name]
        buf = io.BytesIO()
        with wave.open(buf, "wb") as wav:
            if hasattr(pv, "synthesize_wav"):
                pv.synthesize_wav(text, wav)  # piper-tts >= 1.3
            else:
                pv.synthesize(text, wav)
        return buf.getvalue()


class AzureTtsProvider:
    """Azure Speech (cloud, paid). Enabled with VS_TTS_PROVIDER=azure plus
    VS_AZURE_SPEECH_KEY and VS_AZURE_SPEECH_REGION."""

    VOICES = ["es-ES-ElviraNeural", "es-ES-AlvaroNeural", "es-MX-DaliaNeural", "es-MX-JorgeNeural",
              "en-US-JennyNeural", "en-US-GuyNeural", "en-GB-SoniaNeural", "en-GB-RyanNeural"]

    def __init__(self, settings: Settings):
        self.s = settings

    def voices(self) -> list[str]:
        return self.VOICES

    def status(self) -> EngineStatus:
        if not (self.s.azure_speech_key and self.s.azure_speech_region):
            return EngineStatus(False, "Azure Speech", "Falta VS_AZURE_SPEECH_KEY / VS_AZURE_SPEECH_REGION")
        return EngineStatus(True, "Azure Speech", f"Región {self.s.azure_speech_region}")

    def synthesize(self, text: str, language: str, voice: str = "") -> bytes:
        import httpx
        from xml.sax.saxutils import escape

        st = self.status()
        if not st.available:
            raise EngineUnavailable(st.detail)
        voice = voice or ("es-ES-ElviraNeural" if language.startswith("es") else "en-US-JennyNeural")
        lang = "-".join(voice.split("-")[:2])
        ssml = f"<speak version='1.0' xml:lang='{lang}'><voice name='{voice}'>{escape(text)}</voice></speak>"
        r = httpx.post(
            f"https://{self.s.azure_speech_region}.tts.speech.microsoft.com/cognitiveservices/v1",
            headers={"Ocp-Apim-Subscription-Key": self.s.azure_speech_key, "Content-Type": "application/ssml+xml",
                     "X-Microsoft-OutputFormat": "riff-24khz-16bit-mono-pcm", "User-Agent": "VoiceStudio"},
            content=ssml.encode(), timeout=60,
        )
        if r.status_code != 200:
            raise EngineUnavailable(f"Azure Speech respondió HTTP {r.status_code}")
        return r.content


# --------------------------------------------------------------------------
# Translation
# --------------------------------------------------------------------------


class TranslationProvider(Protocol):
    def status(self) -> EngineStatus: ...
    def pairs(self) -> list[str]: ...
    def translate(self, texts: list[str], source: str, target: str) -> list[str]: ...


_SENTENCE_RE = None


def split_sentences(text: str) -> list[str]:
    """Light sentence splitter that keeps decimals ("3.5") and list markers."""
    import re

    global _SENTENCE_RE
    if _SENTENCE_RE is None:
        _SENTENCE_RE = re.compile(r"(?<=[.!?…])\s+(?=[¿¡\"“(A-ZÁÉÍÓÚÑ0-9])")
    parts = [p.strip() for p in _SENTENCE_RE.split(text.strip())]
    return [p for p in parts if p]


class ArgosCT2Provider:
    """Offline ES↔EN translation with Argos Translate models executed directly
    on CTranslate2 + SentencePiece (no PyTorch/spaCy). Models live in
    VS_TRANSLATION_MODELS_DIR/<src>_<tgt>/ (an extracted .argosmodel package);
    download them with scripts/download_translation_models.py."""

    def __init__(self, settings: Settings):
        self.dir = Path(settings.translation_models_dir)
        self._loaded: dict[str, tuple] = {}
        self._lock = threading.Lock()

    def _model_dir(self, pair: str) -> Path | None:
        root = self.dir / pair
        if not root.exists():
            return None
        for cand in [root, *root.iterdir()]:
            if cand.is_dir() and (cand / "model").is_dir() and _tokenizer_file(cand) is not None:
                return cand
        return None

    def pairs(self) -> list[str]:
        if not self.dir.exists():
            return []
        return sorted(p.name for p in self.dir.iterdir() if p.is_dir() and self._model_dir(p.name))

    def status(self) -> EngineStatus:
        if not _installed("ctranslate2"):
            return EngineStatus(False, "Argos (CTranslate2)", "Falta ctranslate2: pip install -r requirements-ai.txt")
        pairs = self.pairs()
        if not pairs:
            return EngineStatus(False, "Argos (CTranslate2)", f"Sin modelos en {self.dir} (scripts/download_translation_models.py)")
        return EngineStatus(True, "Argos (CTranslate2)", "Pares: " + ", ".join(p.replace("_", "→") for p in pairs))

    def _get(self, pair: str):
        with self._lock:
            if pair not in self._loaded:
                d = self._model_dir(pair)
                if d is None:
                    raise EngineUnavailable(f"No hay modelo de traducción instalado para {pair.replace('_', '→')}.")
                import ctranslate2

                # Keep the model's own precision: forcing int8 makes the
                # OPUS-MT based es→en package degenerate into repeated tokens.
                translator = ctranslate2.Translator(str(d / "model"), device="cpu", compute_type="default")
                src, tgt = pair.split("_")
                self._loaded[pair] = (translator, _make_tokenizer(d, src, tgt))
            return self._loaded[pair]

    def translate(self, texts: list[str], source: str, target: str) -> list[str]:
        if source == target:
            return list(texts)
        translator, tok = self._get(f"{source}_{target}")
        out = []
        for text in texts:
            sentences = split_sentences(text)
            if not sentences:
                out.append("")
                continue
            tokens = [tok.encode(s) for s in sentences]
            results = translator.translate_batch(tokens, beam_size=2, max_decoding_length=512)
            out.append(" ".join(tok.decode(r.hypotheses[0]) for r in results).strip())
        return out


class _SentencePieceTokenizer:
    def __init__(self, path: Path):
        import sentencepiece

        self.sp = sentencepiece.SentencePieceProcessor(model_file=str(path))

    def encode(self, text: str) -> list[str]:
        return self.sp.encode(text, out_type=str)

    def decode(self, tokens: list[str]) -> str:
        return self.sp.decode(tokens)


class _MosesBpeTokenizer:
    """OPUS-MT style packages: Moses tokenization + subword-nmt BPE ("@@")."""

    def __init__(self, codes: Path, source: str, target: str):
        from sacremoses import MosesDetokenizer, MosesTokenizer
        from subword_nmt.apply_bpe import BPE

        self.tok = MosesTokenizer(lang=source)
        self.detok = MosesDetokenizer(lang=target)
        with codes.open(encoding="utf-8") as f:
            self.bpe = BPE(f)

    def encode(self, text: str) -> list[str]:
        moses = self.tok.tokenize(text, escape=False, return_str=True)
        return self.bpe.process_line(moses).split()

    def decode(self, tokens: list[str]) -> str:
        words = " ".join(tokens).replace("@@ ", "").replace("@@", "").split()
        return fix_detokenized(self.detok.detokenize(words))


def fix_detokenized(text: str) -> str:
    """Moses detokenization leaves "3 / 4" and "10 - gauge"; restore the
    compact forms so quantities read like the original."""
    import re

    text = re.sub(r"(?<=\d) / (?=\d)", "/", text)
    text = re.sub(r"(?<=\d) - (?=\w)", "-", text)
    return text


def _tokenizer_file(d: Path) -> Path | None:
    for name in ("sentencepiece.model", "bpe.model"):
        if (d / name).exists():
            return d / name
    return None


def _make_tokenizer(d: Path, source: str, target: str):
    f = _tokenizer_file(d)
    if f is None:
        raise EngineUnavailable(f"Paquete de traducción sin tokenizador en {d}")
    if f.name == "sentencepiece.model":
        return _SentencePieceTokenizer(f)
    if not (_installed("sacremoses") and _installed("subword_nmt")):
        raise EngineUnavailable("Este modelo necesita sacremoses y subword-nmt: pip install -r requirements-ai.txt")
    return _MosesBpeTokenizer(f, source, target)


# --------------------------------------------------------------------------
# OCR
# --------------------------------------------------------------------------


class OcrProvider(Protocol):
    def status(self) -> EngineStatus: ...
    def recognize(self, image: bytes) -> str: ...


class RapidOcrProvider:
    """PaddleOCR detection/recognition models executed with ONNX Runtime
    (lighter than the full PaddlePaddle stack, same models)."""

    def __init__(self, settings: Settings):
        self._engine = None
        self._lock = threading.Lock()

    def status(self) -> EngineStatus:
        if not _installed("rapidocr_onnxruntime"):
            return EngineStatus(False, "RapidOCR (PaddleOCR/ONNX)", "No instalado: pip install rapidocr-onnxruntime")
        return EngineStatus(True, "RapidOCR (PaddleOCR/ONNX)", "Modelos incluidos en el paquete")

    def recognize(self, image: bytes) -> str:
        if not _installed("rapidocr_onnxruntime"):
            raise EngineUnavailable("OCR no instalado en el backend (rapidocr-onnxruntime).")
        with self._lock:
            if self._engine is None:
                from rapidocr_onnxruntime import RapidOCR

                self._engine = RapidOCR()
        result, _ = self._engine(image)
        if not result:
            return ""
        return lines_to_text([(box, text) for box, text, _score in result])


class PaddleOcrProvider:
    def __init__(self, settings: Settings):
        self._engine = None

    def status(self) -> EngineStatus:
        ok = _installed("paddleocr")
        return EngineStatus(ok, "PaddleOCR", "Instalado" if ok else "No instalado: pip install paddleocr paddlepaddle")

    def recognize(self, image: bytes) -> str:
        if not _installed("paddleocr"):
            raise EngineUnavailable("PaddleOCR no está instalado.")
        import cv2
        from paddleocr import PaddleOCR

        if self._engine is None:
            self._engine = PaddleOCR(lang="es")
        img = cv2.imdecode(np.frombuffer(image, np.uint8), cv2.IMREAD_COLOR)
        res = self._engine.ocr(img)
        lines = []
        for page in res or []:
            for item in page or []:
                lines.append((item[0], item[1][0]))
        return lines_to_text(lines)


def lines_to_text(items: list[tuple[list, str]]) -> str:
    """Orders OCR boxes top-to-bottom/left-to-right and groups them in lines;
    a vertical gap larger than one line height starts a new paragraph."""
    boxes = []
    for box, text in items:
        ys = [p[1] for p in box]
        xs = [p[0] for p in box]
        boxes.append((min(ys), max(ys), min(xs), text))
    boxes.sort(key=lambda b: (b[0], b[2]))
    lines: list[list] = []
    for b in boxes:
        h = b[1] - b[0]
        if lines and abs(lines[-1][0][0] - b[0]) < h * 0.5:
            lines[-1].append(b)
        else:
            lines.append([b])
    out, prev_bottom, prev_h = [], None, None
    for line in lines:
        line.sort(key=lambda b: b[2])
        top = min(b[0] for b in line)
        h = max(b[1] - b[0] for b in line)
        if prev_bottom is not None and top - prev_bottom > (prev_h or h):
            out.append("")
        out.append(" ".join(b[3] for b in line))
        prev_bottom, prev_h = max(b[1] for b in line), h
    return "\n".join(out).replace("\n\n\n", "\n\n").strip()
