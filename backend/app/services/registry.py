"""Selects the configured provider for each capability (single place to swap
engines). Tests replace these with fakes through FastAPI dependencies."""

from __future__ import annotations

from functools import lru_cache

from ..config import get_settings
from .providers import (
    ArgosCT2Provider,
    AzureTtsProvider,
    TranslationProvider,
    DiarizationProvider,
    FasterWhisperProvider,
    OcrProvider,
    PaddleOcrProvider,
    PiperProvider,
    PyannoteProvider,
    RapidOcrProvider,
    TranscriptionProvider,
    TtsProvider,
)


@lru_cache
def transcription_provider() -> TranscriptionProvider:
    return FasterWhisperProvider(get_settings())


@lru_cache
def diarization_provider() -> DiarizationProvider:
    return PyannoteProvider(get_settings())


@lru_cache
def tts_provider() -> TtsProvider:
    s = get_settings()
    return AzureTtsProvider(s) if s.tts_provider == "azure" else PiperProvider(s)


@lru_cache
def translation_provider() -> TranslationProvider:
    return ArgosCT2Provider(get_settings())


@lru_cache
def ocr_provider() -> OcrProvider:
    s = get_settings()
    return PaddleOcrProvider(s) if s.ocr_provider == "paddleocr" else RapidOcrProvider(s)
