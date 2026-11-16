# Motores de IA y servicios externos — configuración

Todos los motores son intercambiables (`backend/app/services/registry.py` y `lib/core/app_services.dart`). El estado real de cada uno se ve en **Configuración → Backend → Guardar y probar conexión** o en `GET /api/v1/engines`.

| Capacidad | Motor por defecto (gratuito) | Alternativa | Necesita |
|---|---|---|---|
| Voz (lectura) | Voz del sistema (offline) | Piper (backend, offline) · Azure Speech (nube, de pago) | Piper: voces `.onnx` · Azure: clave |
| Transcripción | faster‑whisper (backend) | Reconocedor del dispositivo (Android/iOS, en directo) | Modelo Whisper (se descarga al primer uso) |
| Hablantes | pyannote.audio | Corrección manual en la app | Token de Hugging Face |
| OCR | ML Kit (Android/iOS) · RapidOCR (backend) | PaddleOCR completo | — |
| Traducción ES↔EN | ML Kit (Android/iOS, en el dispositivo) · Argos/CTranslate2 (backend) | — | Modelos: ≈30 MB/idioma (ML Kit) · ≈400 MB (Argos, `scripts\download_translation_models.py`) |
| Conversión de audio | FFmpeg | — | FFmpeg en el PATH |

## faster‑whisper

Instalado con `requirements-ai.txt`. El modelo (`VS_WHISPER_MODEL`, por defecto `small`, ≈460 MB) se descarga de Hugging Face **la primera vez que se transcribe** y queda en caché (`%USERPROFILE%\.cache\huggingface`). Después funciona sin Internet.
- CPU: `VS_WHISPER_COMPUTE_TYPE=int8`. GPU NVIDIA: `VS_WHISPER_DEVICE=cuda`, `VS_WHISPER_COMPUTE_TYPE=float16`.
- Para equipos lentos: `base` o `tiny`. Máxima precisión: `large-v3`.

## Piper (voz neuronal local)

```powershell
cd backend
.\.venv\Scripts\python.exe scripts\download_piper_voices.py   # es_ES-davefx-medium + en_US-lessac-medium (~120 MB)
```
Otras voces: <https://huggingface.co/rhasspy/piper-voices> (copiar `.onnx` y `.onnx.json` a `backend/data/piper`). Revisa la licencia de cada voz en su `MODEL_CARD`.

## pyannote.audio (separación de hablantes)

1. `.\.venv\Scripts\python.exe -m pip install pyannote.audio` (instala PyTorch, ≈1 GB).
2. Crea un token de lectura en <https://huggingface.co/settings/tokens>.
3. Acepta las condiciones de `pyannote/speaker-diarization-3.1` y `pyannote/segmentation-3.0` en Hugging Face.
4. `backend/.env`: `VS_HF_TOKEN=hf_...`

Sin esto, la transcripción funciona igual con un solo hablante y el usuario puede asignar hablantes, dividir fragmentos y ajustar límites a mano.

## Azure Speech (opcional, de pago)

`VS_TTS_PROVIDER=azure`, `VS_AZURE_SPEECH_KEY`, `VS_AZURE_SPEECH_REGION`. Voces neuronales masculinas y femeninas ES/EN (lista en `AzureTtsProvider.VOICES`).

## Gmail y Outlook (OAuth) — pendiente de credenciales

La importación de correos funciona hoy con archivos **.eml** (Gmail: "Descargar mensaje"; Outlook: arrastrar el mensaje a una carpeta) y con "Compartir" en Android. La integración directa por OAuth requiere registrar la app; **no se han inventado credenciales**:
- **Gmail**: Google Cloud Console → nuevo proyecto → habilitar *Gmail API* → pantalla de consentimiento → credenciales OAuth (Android: SHA‑1 del certificado; Windows: "App de escritorio"). Alcance mínimo: `https://www.googleapis.com/auth/gmail.readonly`.
- **Outlook**: Azure Portal → Microsoft Entra ID → Registro de aplicaciones → plataforma "Aplicaciones móviles y de escritorio", redirect `msal{CLIENT_ID}://auth` → permiso delegado `Mail.Read`.
- Solo lectura: Voice Studio no enviará ni eliminará correos.

## Seguridad en producción

- `VS_SECRET_KEY` larga y aleatoria; `VS_REQUIRE_AUTH_FOR_AI=true` si el backend es accesible desde otras máquinas.
- Publica el backend detrás de HTTPS (Caddy, Nginx, o un PaaS). Las builds *release* de Android solo permiten HTTPS; las *debug* permiten HTTP en la red local.
- Base de datos en la nube: `VS_DATABASE_URL=postgresql+psycopg://...`.
