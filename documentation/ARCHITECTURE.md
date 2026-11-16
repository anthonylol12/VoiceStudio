# Arquitectura de Voice Studio

## Visión general

```
┌──────────────────────── Flutter (Android · Windows · iOS) ────────────────────────┐
│ screens/  (11 secciones)        widgets/common.dart (mini‑reproductor, diálogos)   │
│      │                                                                             │
│ core/app_services.dart  ← raíz de composición: crea cada motor tras una interfaz   │
│      │                                                                             │
│ player/ReaderController ── TtsEngine ─┬─ SystemTtsEngine (flutter_tts, offline)    │
│      │  (frase a frase)               └─ BackendTtsEngine (Piper / Azure)          │
│ services/text/  LanguageDetector · SentenceSplitter · SpeechNormalizer (dicc.)    │
│ readers/  DocumentImporter ─ PDF(pdfrx) · Excel · CSV · EML · HTML · WhatsApp     │
│                    └─ OcrEngine ─┬─ MlKitOcrEngine (Android/iOS, offline)          │
│                                  └─ BackendOcrEngine (Windows → RapidOCR)          │
│ audio/  RecorderController (record) · WavWriter                                   │
│ transcription/ LiveTranscriptionController ─┬─ WebSocket → faster‑whisper          │
│                                             └─ speech_to_text (dispositivo)        │
│ services/voice_commands/ CommandParser (ES/EN) · VoiceCommandService (PTT)        │
│ services/sync/ SyncService (concurrencia optimista, lápidas, subidas reanudables) │
│ database/  SQLite (sqflite / sqflite_ffi) + repositorios                           │
└───────────────────────────────────────┬────────────────────────────────────────────┘
                                        │ REST + WebSocket (OpenAPI en /docs)
┌───────────────────────────────── FastAPI backend ──────────────────────────────────┐
│ api/ai.py      /health /engines /transcribe /diarize /ocr /extract /tts /live(WS)  │
│ api/account.py /auth/* /sync/push /sync/changes /sync/history /uploads /account    │
│ services/providers.py  Protocolos: TranscriptionProvider · DiarizationProvider ·   │
│                        TtsProvider · OcrProvider  (+ implementaciones)            │
│ services/registry.py   único punto donde se elige cada proveedor                   │
│ services/live.py       segmentador VAD para transcripción en streaming            │
│ services/extraction.py PyMuPDF · openpyxl · xlrd · csv · BeautifulSoup            │
│ db.py  SQLAlchemy → SQLite (local) o PostgreSQL (nube)                             │
└────────────────────────────────────────────────────────────────────────────────────┘
```

## Decisiones técnicas

| Decisión | Motivo |
|---|---|
| **Lectura frase a frase** en lugar de entregar el documento completo al TTS | "Repetir frase", anterior/siguiente, reanudar exacto y resaltado del texto funcionan igual con cualquier motor (sistema, Piper o nube) y en todas las plataformas. |
| **El texto original nunca se modifica**; `SpeechNormalizer` produce una cadena distinta solo para la voz | Requisito: no alterar instrucciones, cantidades ni numeraciones. Traducciones/resúmenes tienen su propia tabla (`derived_texts`). |
| Normalización numérica **antes** del diccionario técnico | Evita que "AWG" → "A W G" se interprete como "A = amperios". Cubierto por pruebas. |
| Detector de idioma propio por frase (palabras vacías + ortografía) | Sin dependencias, offline, y permite documentos mezclados ES/EN cambiando de voz por frase. |
| `ChangeNotifier` + raíz de composición en lugar de un framework de estado | Menos dependencias y API estable; cada motor se inyecta por interfaz y se sustituye en pruebas (ver `FakeTts`). |
| SQLite con `sqflite` (móvil) y `sqflite_common_ffi` (Windows/pruebas) | Misma base de datos y mismas consultas en todas las plataformas; pruebas en memoria. |
| IDs **UUID v4** + `version` por registro | Sincronización sin colisiones y control de conflictos optimista. |
| OCR: ML Kit en móvil, **RapidOCR** en el backend | ML Kit es gratuito y offline en Android/iOS pero no existe en Windows. RapidOCR ejecuta los modelos de PaddleOCR con ONNX Runtime (≈60 MB frente a >500 MB de PaddlePaddle). PaddleOCR completo sigue disponible con `VS_OCR_PROVIDER=paddleocr`. |
| PDF en el dispositivo con **pdfrx** (PDFium) | Extracción offline en todas las plataformas; si un PDF no tiene capa de texto (escaneado) se envía al backend, que renderiza cada página a 200 ppp y aplica OCR. |
| Transcripción en directo por **WebSocket con PCM 16 kHz** + segmentación por pausas (VAD de energía) | Latencia baja sin modelos de streaming especiales; el cliente guarda el mismo audio en WAV, así cada fragmento queda vinculado a su posición. |
| Diarización en directo **al finalizar** la sesión | pyannote necesita contexto largo; durante la sesión se etiqueta "Persona 1" y al terminar se reasignan hablantes con el audio completo (mensaje `speakers`). |
| Etiquetas genéricas S1, S2… → "Persona 1, Persona 2…" | No se hace identificación biométrica; los nombres los pone el usuario y se guardan por grabación. |
| Comandos de voz **solo pulsar‑para‑hablar** y frases cortas (≤5 palabras) | Evita activaciones accidentales en obra/ruido y garantiza que el micrófono nunca se abre sin acción del usuario. |
| Consentimiento antes de enviar audio/documentos al backend | `AppServices.ensureBackendConsent()`; distingue backend local (no sale del PC) de remoto. |
| Contraseñas con **scrypt** (stdlib) y JWT HS256 | Sin dependencias nativas; `VS_SECRET_KEY` obligatoria en producción (aviso en el arranque). |
| Subidas reanudables por bloques de 1 MB con offset verificado | Grabaciones largas en redes móviles; el servidor rechaza offsets incorrectos (409) y permite reanudar. |
| Conflictos: el servidor **nunca sobrescribe** una versión más nueva; el cliente conserva la copia del servidor como documento aparte | Ningún cambio se pierde en silencio. Historial completo en `sync_item_versions`. |

## Modelo de datos local (SQLite)

`documents`, `document_pages`, `bookmarks`, `derived_texts`, `reading_queue`, `recordings`, `tags`, `recording_tags`, `transcript_segments`, `speakers`, `pronunciations`, `sync_state`. Borrado en cascada (marcadores, segmentos, hablantes…). Esquema versionado en `AppDatabase._migrate`.

## Protocolo de transcripción en directo

1. Cliente abre `ws://HOST/api/v1/live?language=auto|es|en[&token=JWT]`.
2. Envía tramas binarias PCM16 mono 16 kHz.
3. Servidor emite `{"type":"segment","start_ms","end_ms","text","language","speaker"}` al detectar pausas (≥700 ms) o cada 12 s.
4. Cliente envía el texto `stop`; el servidor procesa lo pendiente, emite `{"type":"speakers",...}` si hay diarización y `{"type":"done","duration_ms"}`.
