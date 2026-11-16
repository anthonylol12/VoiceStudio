"""AI endpoints: transcription, diarization, OCR, extraction, TTS, live."""

from __future__ import annotations

import asyncio
import json
import logging
import tempfile
from pathlib import Path

from fastapi import APIRouter, Depends, File, Form, HTTPException, Response, UploadFile, WebSocket, WebSocketDisconnect
from fastapi.concurrency import run_in_threadpool
from pydantic import BaseModel, Field

from ..config import get_settings
from ..services import audio
from ..services.extraction import ExtractionError, extract
from ..services.live import LiveSegmenter
from ..services.providers import (
    DiarizationProvider,
    EngineUnavailable,
    OcrProvider,
    Segment,
    TranscriptionProvider,
    TranslationProvider,
    TtsProvider,
    assign_speakers,
)
from ..security import ai_guard, decode_token
from ..services.registry import (
    diarization_provider,
    ocr_provider,
    transcription_provider,
    translation_provider,
    tts_provider,
)

log = logging.getLogger("voicestudio")
router = APIRouter(tags=["ai"])
guarded = [Depends(ai_guard)]

VERSION = "0.1.0"


def _lang(value: str | None) -> str | None:
    if not value or value == "auto":
        return None
    if value[:2] not in ("es", "en"):
        raise HTTPException(422, "Idioma no compatible (use auto, es o en)")
    return value[:2]


async def _read_limited(file: UploadFile) -> bytes:
    limit = get_settings().max_upload_mb * 1024 * 1024
    data = await file.read(limit + 1)
    if len(data) > limit:
        raise HTTPException(413, f"Archivo demasiado grande (máx. {get_settings().max_upload_mb} MB)")
    return data


@router.get("/health")
def health() -> dict:
    return {"status": "ok", "version": VERSION, "ffmpeg": audio.ffmpeg_path() is not None}


@router.get("/engines")
def engines(
    stt: TranscriptionProvider = Depends(transcription_provider),
    dia: DiarizationProvider = Depends(diarization_provider),
    tts: TtsProvider = Depends(tts_provider),
    ocr: OcrProvider = Depends(ocr_provider),
    tr: TranslationProvider = Depends(translation_provider),
) -> dict:
    ff = audio.ffmpeg_path()
    return {
        "transcription": stt.status().as_dict(),
        "diarization": dia.status().as_dict(),
        "tts": tts.status().as_dict(),
        "ocr": ocr.status().as_dict(),
        "translation": tr.status().as_dict(),
        "ffmpeg": {"available": ff is not None, "name": "FFmpeg", "detail": ff or "No encontrado en el PATH"},
    }


class TranscribeResponse(BaseModel):
    language: str | None
    duration_ms: int
    diarization: str
    segments: list[dict]


def _diarize(samples, segments: list[Segment], dia: DiarizationProvider) -> str:
    try:
        turns = dia.diarize(samples)
        assign_speakers(segments, turns)
        return f"{len({t.speaker for t in turns})} hablante(s) detectado(s) con {dia.status().name}"
    except EngineUnavailable as e:
        return f"no disponible: {e}"


@router.post("/transcribe", response_model=TranscribeResponse, dependencies=guarded)
async def transcribe(
    file: UploadFile = File(...),
    language: str = Form("auto"),
    diarize: bool = Form(True),
    stt: TranscriptionProvider = Depends(transcription_provider),
    dia: DiarizationProvider = Depends(diarization_provider),
) -> TranscribeResponse:
    lang = _lang(language)
    suffix = Path(file.filename or "audio.wav").suffix.lower() or ".wav"
    if suffix not in audio.SUPPORTED_AUDIO:
        raise HTTPException(415, f"Formato de audio no compatible: {suffix}")
    data = await _read_limited(file)
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / f"input{suffix}"
        path.write_bytes(data)
        try:
            samples = await run_in_threadpool(audio.load_audio, path)
        except audio.AudioError as e:
            raise HTTPException(422, str(e)) from e
    try:
        result = await run_in_threadpool(stt.transcribe, samples, lang)
    except EngineUnavailable as e:
        raise HTTPException(503, str(e)) from e
    note = "desactivada"
    if diarize and result.segments:
        note = await run_in_threadpool(_diarize, samples, result.segments, dia)
    return TranscribeResponse(language=result.language, duration_ms=result.duration_ms, diarization=note,
                              segments=[s.as_dict() for s in result.segments])


@router.post("/diarize", dependencies=guarded)
async def diarize_endpoint(file: UploadFile = File(...), dia: DiarizationProvider = Depends(diarization_provider)) -> dict:
    data = await _read_limited(file)
    suffix = Path(file.filename or "a.wav").suffix.lower() or ".wav"
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / f"input{suffix}"
        path.write_bytes(data)
        try:
            samples = await run_in_threadpool(audio.load_audio, path)
            turns = await run_in_threadpool(dia.diarize, samples)
        except audio.AudioError as e:
            raise HTTPException(422, str(e)) from e
        except EngineUnavailable as e:
            raise HTTPException(503, str(e)) from e
    return {"segments": [{"start_ms": t.start_ms, "end_ms": t.end_ms, "speaker": t.speaker} for t in turns]}


@router.post("/ocr", dependencies=guarded)
async def ocr_endpoint(file: UploadFile = File(...), language: str = Form("auto"), ocr: OcrProvider = Depends(ocr_provider)) -> dict:
    data = await _read_limited(file)
    try:
        text = await run_in_threadpool(ocr.recognize, data)
    except EngineUnavailable as e:
        raise HTTPException(503, str(e)) from e
    return {"text": text}


@router.post("/extract", dependencies=guarded)
async def extract_endpoint(file: UploadFile = File(...), ocr: OcrProvider = Depends(ocr_provider)) -> dict:
    data = await _read_limited(file)
    try:
        return await run_in_threadpool(extract, file.filename or "document", data, ocr.recognize)
    except ExtractionError as e:
        raise HTTPException(422, str(e)) from e
    except EngineUnavailable as e:
        raise HTTPException(503, str(e)) from e


class TtsRequest(BaseModel):
    text: str = Field(min_length=1, max_length=5000)
    language: str = "es"
    voice: str = ""


@router.post("/tts", responses={200: {"content": {"audio/wav": {}}}}, dependencies=guarded)
async def tts_endpoint(req: TtsRequest, tts: TtsProvider = Depends(tts_provider)) -> Response:
    try:
        wav = await run_in_threadpool(tts.synthesize, req.text, req.language, req.voice)
    except EngineUnavailable as e:
        raise HTTPException(503, str(e)) from e
    return Response(content=wav, media_type="audio/wav")


class TranslateRequest(BaseModel):
    texts: list[str] = Field(min_length=1, max_length=500)
    source: str = Field(pattern="^(es|en)$")
    target: str = Field(pattern="^(es|en)$")


@router.post("/translate", dependencies=guarded)
async def translate_endpoint(req: TranslateRequest, tr: TranslationProvider = Depends(translation_provider)) -> dict:
    """Paragraph-by-paragraph translation. The client stores the result
    separately from the original document."""
    if sum(len(t) for t in req.texts) > 200_000:
        raise HTTPException(413, "Texto demasiado largo para una sola petición")
    try:
        out = await run_in_threadpool(tr.translate, req.texts, req.source, req.target)
    except EngineUnavailable as e:
        raise HTTPException(503, str(e)) from e
    return {"translations": out, "engine": tr.status().name}


@router.get("/tts/voices")
def tts_voices(tts: TtsProvider = Depends(tts_provider)) -> dict:
    return {"provider": tts.status().name, "voices": tts.voices()}


@router.websocket("/live")
async def live(
    ws: WebSocket,
    stt: TranscriptionProvider = Depends(transcription_provider),
    dia: DiarizationProvider = Depends(diarization_provider),
) -> None:
    """Protocol: client sends binary PCM16 mono 16 kHz frames and the text
    message "stop". Server sends JSON: {"type": "segment"|"speakers"|"error"|"done", ...}."""
    if get_settings().require_auth_for_ai:
        try:
            decode_token(ws.query_params.get("token", ""))
        except HTTPException:
            await ws.close(code=4401)
            return
    await ws.accept()
    lang = ws.query_params.get("language")
    lang = None if not lang or lang == "auto" else lang[:2]
    seg = LiveSegmenter()
    queue: asyncio.Queue = asyncio.Queue()
    segments: list[Segment] = []

    async def worker() -> None:
        while True:
            utt = await queue.get()
            if utt is None:
                return
            try:
                result = await run_in_threadpool(stt.transcribe, utt.samples, lang)
            except EngineUnavailable as e:
                await ws.send_text(json.dumps({"type": "error", "detail": str(e)}))
                continue
            except Exception as e:  # keep the session alive
                log.exception("live transcription failed")
                await ws.send_text(json.dumps({"type": "error", "detail": f"Error de transcripción: {e}"}))
                continue
            for s in result.segments:
                s.start_ms += utt.start_ms
                s.end_ms = min(s.end_ms + utt.start_ms, utt.end_ms)
                segments.append(s)
                await ws.send_text(json.dumps({"type": "segment", **s.as_dict()}))

    task = asyncio.create_task(worker())
    try:
        while True:
            msg = await ws.receive()
            if msg["type"] == "websocket.disconnect":
                raise WebSocketDisconnect()
            if msg.get("bytes"):
                for u in seg.feed(msg["bytes"]):
                    await queue.put(u)
            elif msg.get("text") == "stop":
                last = seg.flush()
                if last is not None:
                    await queue.put(last)
                await queue.put(None)
                await task
                if segments and dia.status().available:
                    note = await run_in_threadpool(_diarize, seg.full_audio(), segments, dia)
                    await ws.send_text(json.dumps({"type": "speakers", "detail": note,
                                                   "segments": [{"speaker": s.speaker} for s in segments]}))
                await ws.send_text(json.dumps({"type": "done", "duration_ms": seg.total_ms}))
                await ws.close()
                return
    except WebSocketDisconnect:
        task.cancel()
