import io
import json
import wave
from pathlib import Path

import numpy as np
import pytest

from app.services import audio
from app.services.extraction import extract, table_to_text
from app.services.live import LiveSegmenter
from app.services.providers import Segment, Turn, assign_speakers, lines_to_text

from .conftest import speech_like, to_pcm16


def wav_bytes(samples: np.ndarray) -> bytes:
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(16000)
        w.writeframes(to_pcm16(samples))
    return buf.getvalue()


def test_health_and_engines(client):
    assert client.get("/api/v1/health").json()["status"] == "ok"
    eng = client.get("/api/v1/engines").json()
    assert eng["transcription"]["available"] is True
    assert set(eng) == {"transcription", "diarization", "tts", "ocr", "translation", "ffmpeg"}


def test_openapi_document(client):
    paths = client.get("/openapi.json").json()["paths"]
    for p in ["/api/v1/transcribe", "/api/v1/tts", "/api/v1/sync/push", "/api/v1/uploads"]:
        assert p in paths


@pytest.mark.skipif(audio.ffmpeg_path() is None, reason="FFmpeg required")
def test_transcribe_with_diarization(client):
    data = wav_bytes(speech_like(4))
    r = client.post("/api/v1/transcribe", files={"file": ("a.wav", data, "audio/wav")}, data={"language": "auto", "diarize": "true"})
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["duration_ms"] == 4000
    # Speakers renumbered by first appearance: SPK_B -> S1, SPK_A -> S2
    assert [s["speaker"] for s in body["segments"]] == ["S1", "S2"]
    assert body["segments"][1]["start_ms"] == 2000


def test_transcribe_rejects_bad_input(client):
    r = client.post("/api/v1/transcribe", files={"file": ("a.exe", b"xx")})
    assert r.status_code == 415
    r = client.post("/api/v1/transcribe", files={"file": ("a.wav", b"xx")}, data={"language": "fr"})
    assert r.status_code == 422


def test_tts(client):
    r = client.post("/api/v1/tts", json={"text": "Hola", "language": "es"})
    assert r.status_code == 200 and r.headers["content-type"] == "audio/wav"
    assert client.get("/api/v1/tts/voices").json()["voices"] == ["es_ES-test", "en_US-test"]


def test_live_websocket(client, fakes):
    speech = to_pcm16(speech_like(2.0))
    silence = to_pcm16(np.zeros(16000, dtype=np.float32))
    with client.websocket_connect("/api/v1/live?language=es") as ws:
        for chunk in [silence[:8000], speech, silence, speech]:
            for i in range(0, len(chunk), 3200):
                ws.send_bytes(chunk[i:i + 3200])
        ws.send_text("stop")
        msgs = []
        while True:
            m = json.loads(ws.receive_text())
            msgs.append(m)
            if m["type"] == "done":
                break
    segs = [m for m in msgs if m["type"] == "segment"]
    assert len(segs) == 4  # 2 utterances x 2 fake segments
    assert segs[2]["start_ms"] >= 2500  # second utterance keeps absolute offset
    assert any(m["type"] == "speakers" for m in msgs)
    assert msgs[-1]["duration_ms"] == 5250  # 0.25 + 2 + 1 + 2 s


def test_auth_flow(client):
    r = client.post("/api/v1/auth/register", json={"email": "x@example.com", "password": "corta"})
    assert r.status_code == 422
    r = client.post("/api/v1/auth/register", json={"email": "Luis@Example.com", "password": "una-clave-larga"})
    assert r.status_code == 200
    assert client.post("/api/v1/auth/register", json={"email": "luis@example.com", "password": "una-clave-larga"}).status_code == 409
    assert client.post("/api/v1/auth/login", json={"email": "luis@example.com", "password": "mala-clave-xx"}).status_code == 401
    tok = client.post("/api/v1/auth/login", json={"email": "luis@example.com", "password": "una-clave-larga"}).json()["access_token"]
    assert client.get("/api/v1/auth/me", headers={"Authorization": f"Bearer {tok}"}).json()["email"] == "luis@example.com"
    assert client.get("/api/v1/auth/me").status_code == 401
    assert client.get("/api/v1/auth/me", headers={"Authorization": "Bearer basura"}).status_code == 401


def test_sync_conflicts_history_and_deletion(client, auth):
    item = {"entity": "document", "id": "d1", "base_version": 0, "payload": {"title": "v1"}}
    r = client.post("/api/v1/sync/push", json={"items": [item]}, headers=auth).json()["results"][0]
    assert r == {"entity": "document", "id": "d1", "status": "ok", "server_version": 1}
    # Stale write from another device -> conflict, server copy returned
    r = client.post("/api/v1/sync/push", json={"items": [{**item, "payload": {"title": "otro"}}]}, headers=auth).json()["results"][0]
    assert r["status"] == "conflict" and r["server_payload"] == {"title": "v1"}
    # Correct base version -> accepted
    r = client.post("/api/v1/sync/push", json={"items": [{**item, "base_version": 1, "payload": {"title": "v2"}}]}, headers=auth).json()["results"][0]
    assert r["server_version"] == 2
    ch = client.get("/api/v1/sync/changes?since=0", headers=auth).json()
    assert ch["items"][0]["payload"] == {"title": "v2"} and ch["cursor"] == 2
    assert client.get(f"/api/v1/sync/changes?since={ch['cursor']}", headers=auth).json()["items"] == []
    hist = client.get("/api/v1/sync/history/document/d1", headers=auth).json()["versions"]
    assert [v["payload"]["title"] for v in hist] == ["v1", "v2"]
    # Synced deletion
    client.post("/api/v1/sync/push", json={"items": [{**item, "base_version": 2, "deleted": True}]}, headers=auth)
    assert client.get("/api/v1/sync/changes?since=2", headers=auth).json()["items"][0]["deleted"] is True
    # Isolation between users
    other = client.post("/api/v1/auth/register", json={"email": "b@example.com", "password": "otra-clave-larga"}).json()["access_token"]
    assert client.get("/api/v1/sync/changes", headers={"Authorization": f"Bearer {other}"}).json()["items"] == []
    assert client.post("/api/v1/sync/push", json={"items": [{**item, "entity": "malware"}]}, headers=auth).status_code == 422


def test_resumable_upload_and_account_deletion(client, auth):
    data = bytes(range(256)) * 40  # 10240 bytes
    init = client.post("/api/v1/uploads", json={"filename": "rec.m4a", "size": len(data), "entity_id": "r1"}, headers=auth).json()
    uid = init["upload_id"]
    assert client.put(f"/api/v1/uploads/{uid}?offset=0", content=data[:4000], headers=auth).json()["offset"] == 4000
    # Connection lost: client asks again and resumes from the server offset
    again = client.post("/api/v1/uploads", json={"filename": "rec.m4a", "size": len(data), "entity_id": "r1"}, headers=auth).json()
    assert again == {"upload_id": uid, "offset": 4000}
    assert client.put(f"/api/v1/uploads/{uid}?offset=0", content=data[:10], headers=auth).status_code == 409
    assert client.post(f"/api/v1/uploads/{uid}/complete", headers=auth).status_code == 409
    client.put(f"/api/v1/uploads/{uid}?offset=4000", content=data[4000:], headers=auth)
    assert client.post(f"/api/v1/uploads/{uid}/complete", headers=auth).status_code == 200
    assert client.delete("/api/v1/account", headers=auth).json() == {"deleted": True}
    assert client.get("/api/v1/auth/me", headers=auth).status_code == 401


def test_missing_secret_key_gets_a_random_persistent_one(tmp_path):
    from app.config import DEV_SECRET, local_secret

    k1 = local_secret(tmp_path / ".secret_key")
    k2 = local_secret(tmp_path / ".secret_key")
    assert k1 == k2 and len(k1) >= 48 and k1 != DEV_SECRET
    assert local_secret(tmp_path / "other" / ".secret_key") != k1


def test_empty_secret_from_env_example_is_replaced(monkeypatch):
    from app.config import Settings, get_settings

    monkeypatch.setenv("VS_SECRET_KEY", "")
    get_settings.cache_clear()
    try:
        assert len(get_settings().secret_key) >= 48
    finally:
        monkeypatch.undo()
        get_settings.cache_clear()
    assert Settings  # imported for clarity


def test_ai_auth_guard(client, monkeypatch):
    from app.config import get_settings

    monkeypatch.setattr(get_settings(), "require_auth_for_ai", True)
    assert client.post("/api/v1/tts", json={"text": "Hola"}).status_code == 401


# ---------------------------------------------------------------- units


def test_assign_speakers_by_overlap():
    segs = [Segment(0, 1000, "a"), Segment(1000, 3000, "b"), Segment(3100, 3500, "c"), Segment(9000, 9500, "d")]
    turns = [Turn(0, 1200, "X"), Turn(1200, 3050, "Y"), Turn(3050, 4000, "X")]
    out = assign_speakers(segs, turns)
    assert [s.speaker for s in out] == ["S1", "S2", "S1", "S1"]


def test_live_segmenter_cuts_on_pauses_and_max_length():
    seg = LiveSegmenter(max_ms=3000)
    out = seg.feed(to_pcm16(np.zeros(8000, np.float32)))
    out += seg.feed(to_pcm16(speech_like(1.5)))
    out += seg.feed(to_pcm16(np.zeros(16000, np.float32)))
    assert len(out) == 1 and 0 <= out[0].start_ms <= 500  # 500 ms pre-roll before the speech at 500 ms
    out = seg.feed(to_pcm16(speech_like(7)))  # long monologue -> forced cuts
    assert len(out) == 2
    assert seg.flush() is not None
    assert seg.total_ms == 10000


def test_table_and_extraction():
    t = table_to_text([["Material", "Cantidad"], ["Cable THHN", "500"]])
    assert t == "Fila 1. Material: Cable THHN; Cantidad: 500."
    r = extract("orden.csv", "Material,Cantidad\nTubo EMT,20\n".encode())
    assert r["kind"] == "csv" and "Tubo EMT" in r["pages"][0]["text"]
    r = extract("p.html", b"<html><title>T</title><body><nav>x</nav><article><p>Hola mundo</p></article></body></html>")
    assert r["title"] == "T" and r["pages"][0]["text"] == "Hola mundo"
    with pytest.raises(ValueError):
        extract("x.doc", b"..")


def test_pdf_and_excel_extraction():
    import openpyxl
    import pymupdf

    doc = pymupdf.open()
    for text in ["Instalar panel de 200 A.", "Página dos."]:
        page = doc.new_page()
        page.insert_text((72, 72), text)
    r = extract("orden.pdf", doc.tobytes())
    assert [p["text"] for p in r["pages"]] == ["Instalar panel de 200 A.", "Página dos."]

    wb = openpyxl.Workbook()
    ws = wb.active
    ws.append(["Material", "Cantidad"])
    ws.append(["Breaker 20A", 4])
    buf = io.BytesIO()
    wb.save(buf)
    r = extract("m.xlsx", buf.getvalue())
    assert r["pages"][0]["text"] == "Fila 1. Material: Breaker 20A; Cantidad: 4."


class FakeTranslator:
    def status(self):
        from app.services.providers import EngineStatus

        return EngineStatus(True, "fake-tr", "test")

    def pairs(self):
        return ["es_en"]

    def translate(self, texts, source, target):
        return [f"[{target}] {t}" for t in texts]


def test_translate_endpoint(client):
    from app.services import registry

    client.app.dependency_overrides[registry.translation_provider] = FakeTranslator
    r = client.post("/api/v1/translate", json={"texts": ["Hola.", "Instalar 3 paneles."], "source": "es", "target": "en"})
    assert r.status_code == 200
    assert r.json() == {"translations": ["[en] Hola.", "[en] Instalar 3 paneles."], "engine": "fake-tr"}
    assert client.post("/api/v1/translate", json={"texts": ["x"], "source": "fr", "target": "en"}).status_code == 422
    assert "translation" in client.get("/api/v1/engines").json()


def test_translation_without_models_is_503(client, tmp_path):
    from app.config import get_settings
    from app.services import registry
    from app.services.providers import ArgosCT2Provider

    s = get_settings().model_copy(update={"translation_models_dir": tmp_path})
    client.app.dependency_overrides[registry.translation_provider] = lambda: ArgosCT2Provider(s)
    r = client.post("/api/v1/translate", json={"texts": ["Hola."], "source": "es", "target": "en"})
    assert r.status_code == 503 and "modelo" in r.json()["detail"]


def test_live_segmenter_keeps_quiet_speech_from_a_real_microphone_level():
    """Regression: speech at ~-42 dBFS RMS over a -60 dBFS noise floor (as
    measured with a Windows laptop microphone) must be detected entirely."""
    rng = np.random.default_rng(1)

    def noise(sec):
        return (rng.normal(0, 0.001, int(16000 * sec))).astype(np.float32)

    def quiet_speech(sec):
        t = np.arange(int(16000 * sec)) / 16000
        env = 0.5 + 0.5 * np.sin(2 * np.pi * 3 * t)  # syllable-like amplitude envelope
        return (0.011 * env * np.sin(2 * np.pi * 180 * t)).astype(np.float32) + noise(sec)

    seg = LiveSegmenter()
    audio = np.concatenate([noise(1.5), quiet_speech(3.0), noise(1.5), quiet_speech(2.0), noise(1.5)])
    out = []
    for i in range(0, len(audio), 1600):
        out += seg.feed(to_pcm16(audio[i:i + 1600]))
    last = seg.flush()
    if last:
        out.append(last)
    assert len(out) == 2, [(u.start_ms, u.end_ms) for u in out]
    first, second = out
    assert first.start_ms <= 1500 and first.end_ms >= 4400  # whole phrase incl. onset
    assert 4500 <= second.start_ms <= 6000 and second.end_ms >= 7900


def test_real_diarization_provider_degrades_gracefully():
    """Without pyannote/token, transcription must still succeed (one speaker)."""
    from app.api.ai import _diarize
    from app.config import get_settings
    from app.services.providers import PyannoteProvider

    p = PyannoteProvider(get_settings())
    if p.status().available:
        pytest.skip("pyannote configured on this machine")
    segs = [Segment(0, 1000, "hola")]
    note = _diarize(np.zeros(16000, np.float32), segs, p)
    assert note.startswith("no disponible") and segs[0].speaker == "S1"


def test_whisper_falls_back_to_cpu_when_cuda_libraries_are_missing():
    from app.config import get_settings
    from app.services.providers import FasterWhisperProvider, Transcription

    p = FasterWhisperProvider(get_settings())
    calls = []

    def fake(samples, language=None):
        calls.append(p.device)
        if p.device != "cpu":
            raise RuntimeError("Library cublas64_12.dll is not found or cannot be loaded")
        return Transcription("en", 1000, [])

    p._transcribe = fake
    assert p.transcribe(np.zeros(16000, np.float32)).language == "en"
    assert calls == ["auto", "cpu"] and p.device == "cpu"

    def other(samples, language=None):
        raise RuntimeError("something else")

    p._transcribe = other
    with pytest.raises(RuntimeError, match="something else"):
        p.transcribe(np.zeros(16000, np.float32))


def test_fix_detokenized_fractions():
    from app.services.providers import fix_detokenized

    assert fix_detokenized("the 3 / 4 inch EMT and 10 - gauge wire") == "the 3/4 inch EMT and 10-gauge wire"
    assert fix_detokenized("A / B") == "A / B"


@pytest.mark.skipif(not (Path(__file__).parent.parent / "data" / "translate" / "es_en").exists(), reason="modelo es→en no descargado")
def test_real_translation_es_en():
    from app.config import get_settings
    from app.services.providers import ArgosCT2Provider

    out = ArgosCT2Provider(get_settings()).translate(["Mañana necesitamos comenzar la instalación del panel eléctrico."], "es", "en")
    assert "Tomorrow" in out[0] and "panel" in out[0]


def test_split_sentences_keeps_decimals():
    from app.services.providers import split_sentences

    assert split_sentences("Cortar 3.5 m de tubo. ¿Listo? Sí.") == ["Cortar 3.5 m de tubo.", "¿Listo?", "Sí."]


def test_real_providers_report_status_without_crashing():
    """Engines that are missing or unconfigured must report status, not raise."""
    from app.config import get_settings
    from app.services.providers import FasterWhisperProvider, PiperProvider, PyannoteProvider, RapidOcrProvider

    s = get_settings()
    for p in (FasterWhisperProvider(s), PyannoteProvider(s), PiperProvider(s), RapidOcrProvider(s)):
        st = p.status()
        assert isinstance(st.available, bool) and st.detail


def test_ocr_line_grouping():
    items = [
        ([[10, 50], [90, 50], [90, 70], [10, 70]], "segunda"),
        ([[10, 10], [60, 10], [60, 30], [10, 30]], "Primera"),
        ([[70, 12], [120, 12], [120, 30], [70, 30]], "línea"),
        ([[10, 140], [90, 140], [90, 160], [10, 160]], "Párrafo nuevo"),
    ]
    assert lines_to_text(items) == "Primera línea\nsegunda\n\nPárrafo nuevo"
