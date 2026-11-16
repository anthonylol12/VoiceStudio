# Voice Studio

Asistente de voz para leer documentos y órdenes de trabajo en voz alta, grabar conversaciones, transcribirlas en tiempo real y separar a los hablantes. Pensado para trabajar con las manos ocupadas.

- **App**: Flutter 3.50 / Dart 3.14 — Android y Windows (prioridad), proyecto iOS preparado.
- **Backend**: Python 3.12 + FastAPI — faster‑whisper, pyannote.audio, Piper, RapidOCR (modelos PaddleOCR), PyMuPDF, openpyxl, FFmpeg.
- **Datos**: SQLite local (sin conexión) · SQLite o PostgreSQL en el servidor.

📖 **[Manual de uso (PC y teléfono)](documentation/MANUAL_USUARIO.md)**

## Módulos

| Módulo | Estado |
|---|---|
| Smart Reader: PDF, imágenes (OCR), Excel XLSX/XLS, CSV, correo .eml, chats de WhatsApp (.txt/.zip y "Compartir"), páginas web, texto | ✅ |
| Reproductor: frase a frase, repetir, anterior/siguiente, párrafo, página, 0.75–2.0x, volumen, marcadores, reanudar, cola, ES/EN/auto, motor local o backend | ✅ |
| Diccionario de pronunciación técnico (EMT, THHN, AWG…) y lectura de medidas, fracciones, fechas | ✅ |
| Grabadora manual con indicador, duración, nivel, micrófono y almacenamiento | ✅ |
| Transcripción en directo (Whisper por WebSocket, o reconocedor del dispositivo) | ✅ |
| Transcripción de archivos WAV/MP3/M4A/AAC/FLAC/OGG con marcas de tiempo e idioma | ✅ |
| Hablantes: Persona 1/2…, renombrar, reasignar, dividir y ajustar límites; pyannote opcional | ✅ (pyannote requiere token) |
| Biblioteca: buscar (también dentro de transcripciones), etiquetas, favoritos, notas, orden, exportar TXT/SRT/JSON/audio | ✅ |
| Pedidos (órdenes de trabajo con estado) | ✅ |
| Comandos de voz (pulsar para hablar) | ✅ |
| Sincronización: cuentas, selección por elemento, conflictos, historial, lápidas, subidas reanudables, borrado de cuenta | ✅ |
| Reproducción en segundo plano, pantalla de bloqueo, botones Bluetooth y notificación persistente (Android/iOS) | ✅ (pendiente de probar en dispositivo) |
| Traducción ES↔EN sin conexión, guardada aparte del original, con aviso si cambian los números y protección de los términos del diccionario técnico | ✅ (modelos se descargan aparte) |
| Interfaz en español e inglés (selector en Configuración) | ✅ |
| Gmail/Outlook por OAuth, resumen automático | ⏳ pendiente (requiere credenciales / motor) |

## Inicio rápido (Windows)

```powershell
# 1. Backend (opcional para leer con voz del sistema; necesario para transcribir)
cd backend
.\run_server.ps1                      # crea .venv, instala dependencias y arranca en 127.0.0.1:8765

# 2. App
cd ..
flutter pub get
flutter run -d windows
```

Más detalles: [documentation/MANUAL_USUARIO.md](documentation/MANUAL_USUARIO.md) · [documentation/BUILD.md](documentation/BUILD.md) · [documentation/ENGINES.md](documentation/ENGINES.md) · [documentation/ARCHITECTURE.md](documentation/ARCHITECTURE.md) · [documentation/PROGRESS.md](documentation/PROGRESS.md) · API: `http://127.0.0.1:8765/docs`.

## Estructura

```
lib/
  core/            settings, tema, raíz de composición (AppServices)
  models/          entidades (UUID + versión)
  database/        SQLite: esquema/migraciones y repositorios
  readers/         importadores: PDF, imagen/OCR, Excel, CSV, EML, HTML, WhatsApp
  services/text/   detector de idioma, divisor de frases, normalizador para voz
  services/tts/    motores de voz intercambiables
  services/backend cliente REST/WebSocket
  services/sync/   sincronización
  services/voice_commands/
  player/          controlador de lectura
  audio/           grabadora, escritor WAV
  transcription/   transcripción en directo, exportación
  screens/ widgets/
backend/
  app/api/         rutas REST y WebSocket
  app/services/    proveedores de IA, extracción, segmentador en directo
  app/db.py        modelos SQLAlchemy
  tests/
test/              pruebas Flutter (unidad + integración con SQLite en memoria)
documentation/
```

## Pruebas

```powershell
flutter test                                  # 54 pruebas (+1 de integración con el backend real)
cd backend; .\.venv\Scripts\python.exe -m pytest   # 24 pruebas
```

## Privacidad

La grabación solo empieza al pulsar un botón; no hay activación automática. Nada sale del dispositivo sin consentimiento explícito, y solo se sincroniza lo que el usuario marca. No se hace identificación biométrica de hablantes. Informa y obtén el consentimiento de las personas antes de grabarlas, según la ley aplicable.
