"""Downloads the default Spanish and English Piper voices into data/piper.

Source: https://huggingface.co/rhasspy/piper-voices (MIT-licensed models; check
each voice's MODEL_CARD for its dataset licence). ~60 MB per voice.
Run:  .venv\\Scripts\\python.exe scripts\\download_piper_voices.py
"""

from __future__ import annotations

import sys
import urllib.request
from pathlib import Path

BASE = "https://huggingface.co/rhasspy/piper-voices/resolve/main"
VOICES = {
    "es_ES-davefx-medium": "es/es_ES/davefx/medium",
    "en_US-lessac-medium": "en/en_US/lessac/medium",
}

target = Path(__file__).resolve().parent.parent / "data" / "piper"
target.mkdir(parents=True, exist_ok=True)
selected = sys.argv[1:] or list(VOICES)
for name in selected:
    if name not in VOICES:
        sys.exit(f"Voz desconocida: {name}. Opciones: {', '.join(VOICES)}")
    for ext in (".onnx", ".onnx.json"):
        dest = target / f"{name}{ext}"
        if dest.exists():
            print(f"ya existe {dest.name}")
            continue
        url = f"{BASE}/{VOICES[name]}/{name}{ext}"
        print(f"descargando {url}")
        urllib.request.urlretrieve(url, dest)
print(f"Voces en {target}")
