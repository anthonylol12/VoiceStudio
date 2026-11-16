"""Runtime configuration (environment variables or backend/.env)."""

from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

BASE_DIR = Path(__file__).resolve().parent.parent


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=BASE_DIR / ".env", env_prefix="VS_", extra="ignore")

    # Database: SQLite for local/offline use, PostgreSQL in the cloud, e.g.
    # postgresql+psycopg://user:pass@host:5432/voicestudio
    database_url: str = f"sqlite:///{(BASE_DIR / 'data' / 'voicestudio.db').as_posix()}"
    storage_dir: Path = BASE_DIR / "data" / "storage"

    # Auth signing key. If VS_SECRET_KEY is not set, a random per-install key
    # is generated in data/.secret_key (never committed).
    secret_key: str = "dev-only-change-me"
    token_minutes: int = 60 * 24 * 14
    min_password_length: int = 10

    # Speech recognition (faster-whisper)
    whisper_model: str = "small"  # tiny | base | small | medium | large-v3
    whisper_device: str = "auto"  # auto | cpu | cuda
    whisper_compute_type: str = "int8"

    # Speaker diarization (pyannote.audio). Requires a Hugging Face token with
    # access granted to the pyannote model.
    hf_token: str = ""
    diarization_model: str = "pyannote/speaker-diarization-3.1"

    # Text to speech
    tts_provider: str = "piper"  # piper | azure
    piper_voices_dir: Path = BASE_DIR / "data" / "piper"
    piper_default_es: str = "es_ES-davefx-medium"
    piper_default_en: str = "en_US-lessac-medium"
    azure_speech_key: str = ""
    azure_speech_region: str = ""

    # Offline translation (Argos models on CTranslate2)
    translation_models_dir: Path = BASE_DIR / "data" / "translate"

    # OCR provider: rapidocr (PaddleOCR models on ONNX runtime) | paddleocr
    ocr_provider: str = "rapidocr"

    # When the backend is exposed beyond this computer, require a login token
    # for AI endpoints too (transcription, OCR, TTS, live).
    require_auth_for_ai: bool = False

    cors_origins: list[str] = ["*"]
    max_upload_mb: int = 1024
    ffmpeg_binary: str = "ffmpeg"


@lru_cache
def get_settings() -> Settings:
    s = Settings()
    s.storage_dir.mkdir(parents=True, exist_ok=True)
    s.piper_voices_dir.mkdir(parents=True, exist_ok=True)
    if s.database_url.startswith("sqlite:///"):
        Path(s.database_url.removeprefix("sqlite:///")).parent.mkdir(parents=True, exist_ok=True)
    # Missing, empty (e.g. copied .env.example) or weak keys are never used.
    if s.secret_key == DEV_SECRET or len(s.secret_key) < 32:
        s.secret_key = local_secret(BASE_DIR / "data" / ".secret_key")
    return s


DEV_SECRET = "dev-only-change-me"


def local_secret(path: Path) -> str:
    """Random signing key created once per installation and kept out of git.

    The repository is public, so a hard-coded default key would let anyone
    forge login tokens for a backend that was started without VS_SECRET_KEY.
    """
    import secrets

    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        key = path.read_text(encoding="utf-8").strip()
        if len(key) >= 32:
            return key
    key = secrets.token_urlsafe(48)
    path.write_text(key, encoding="utf-8")
    try:
        path.chmod(0o600)
    except OSError:
        pass
    return key
