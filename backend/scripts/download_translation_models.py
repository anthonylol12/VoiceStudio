"""Downloads the Argos Translate ES→EN and EN→ES packages (~90 MB each) and
extracts them into data/translate/<src>_<tgt>/ for the CTranslate2 provider.

Models: https://github.com/argosopentech/argospm-index (MIT/CC licences per
package, see each package's README). Run:
    .venv\\Scripts\\python.exe scripts\\download_translation_models.py
"""

from __future__ import annotations

import json
import shutil
import sys
import tempfile
import urllib.request
import zipfile
from pathlib import Path

INDEX = "https://raw.githubusercontent.com/argosopentech/argospm-index/main/index.json"
PAIRS = [("es", "en"), ("en", "es")]

target_root = Path(__file__).resolve().parent.parent / "data" / "translate"
target_root.mkdir(parents=True, exist_ok=True)

with urllib.request.urlopen(INDEX, timeout=60) as r:
    index = json.load(r)

for src, tgt in PAIRS:
    dest = target_root / f"{src}_{tgt}"
    if dest.exists() and (any(dest.rglob("sentencepiece.model")) or any(dest.rglob("bpe.model"))):
        print(f"ya instalado: {src}→{tgt}")
        continue
    pkg = next((p for p in index if p.get("from_code") == src and p.get("to_code") == tgt), None)
    if pkg is None:
        sys.exit(f"No se encontró el paquete {src}→{tgt} en el índice")
    with tempfile.TemporaryDirectory() as tmp:
        archive = Path(tmp) / "model.argosmodel"
        for url in pkg["links"]:  # mirrors, in order
            print(f"descargando {src}→{tgt} v{pkg.get('package_version')} desde {url}")
            try:
                req = urllib.request.Request(url, headers={"User-Agent": "VoiceStudio-model-downloader/1.0"})
                with urllib.request.urlopen(req, timeout=120) as r, archive.open("wb") as f:
                    shutil.copyfileobj(r, f)
                break
            except OSError as e:
                print(f"  falló ({e}); probando el siguiente enlace")
        else:
            sys.exit(f"No se pudo descargar {src}→{tgt}")
        with zipfile.ZipFile(archive) as z:
            for name in z.namelist():  # refuse path traversal
                if name.startswith("/") or ".." in Path(name).parts:
                    sys.exit(f"Ruta no segura en el paquete: {name}")
            z.extractall(tmp)
        candidates = [p.parent for p in Path(tmp).rglob("*.model") if p.name in ("sentencepiece.model", "bpe.model")]
        if not candidates:
            sys.exit(f"El paquete {src}→{tgt} no contiene un tokenizador reconocible")
        extracted = candidates[0]
        if dest.exists():
            shutil.rmtree(dest)
        shutil.copytree(extracted, dest)
    print(f"instalado en {dest}")
