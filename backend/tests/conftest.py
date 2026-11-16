import os
import tempfile

import numpy as np
import pytest

os.environ.setdefault("VS_STORAGE_DIR", tempfile.mkdtemp(prefix="vs_storage_"))
os.environ.setdefault("VS_PIPER_VOICES_DIR", tempfile.mkdtemp(prefix="vs_piper_"))
os.environ.setdefault("VS_SECRET_KEY", "test-secret-key-with-at-least-32-bytes!!")

from fastapi.testclient import TestClient  # noqa: E402

from app import db as dbmod  # noqa: E402
from app.main import create_app  # noqa: E402
from app.services import registry  # noqa: E402
from app.services.providers import EngineStatus, Segment, Transcription, Turn  # noqa: E402


class FakeStt:
    """Deterministic stand-in for Whisper used only in tests."""

    def __init__(self):
        self.calls = []

    def status(self):
        return EngineStatus(True, "fake-stt", "test")

    def transcribe(self, samples, language=None):
        self.calls.append((len(samples), language))
        dur = int(len(samples) / 16000 * 1000)
        half = dur // 2
        return Transcription(language or "es", dur, [
            Segment(0, half, "Mañana necesitamos comenzar la instalación.", language or "es"),
            Segment(half, dur, "¿Ya tenemos todos los materiales?", language or "es"),
        ])


class FakeDia:
    def status(self):
        return EngineStatus(True, "fake-dia", "test")

    def diarize(self, samples):
        dur = int(len(samples) / 16000 * 1000)
        return [Turn(0, dur // 2, "SPK_B"), Turn(dur // 2, dur, "SPK_A")]


class FakeTts:
    def status(self):
        return EngineStatus(True, "fake-tts", "test")

    def voices(self):
        return ["es_ES-test", "en_US-test"]

    def synthesize(self, text, language, voice=""):
        return b"RIFF" + text.encode()


@pytest.fixture()
def fakes():
    return {"stt": FakeStt(), "dia": FakeDia(), "tts": FakeTts()}


@pytest.fixture()
def client(fakes):
    dbmod._engine = None
    dbmod.init_engine("sqlite://")
    app = create_app()
    app.dependency_overrides[registry.transcription_provider] = lambda: fakes["stt"]
    app.dependency_overrides[registry.diarization_provider] = lambda: fakes["dia"]
    app.dependency_overrides[registry.tts_provider] = lambda: fakes["tts"]
    with TestClient(app) as c:
        yield c


@pytest.fixture()
def auth(client):
    r = client.post("/api/v1/auth/register", json={"email": "ana@example.com", "password": "una-clave-larga"})
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


def speech_like(seconds: float, sr: int = 16000) -> np.ndarray:
    t = np.arange(int(seconds * sr)) / sr
    return (0.3 * np.sin(2 * np.pi * 220 * t)).astype(np.float32)


def to_pcm16(samples: np.ndarray) -> bytes:
    return (np.clip(samples, -1, 1) * 32767).astype("<i2").tobytes()
