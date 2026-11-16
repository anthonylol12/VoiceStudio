# Registro de progreso

## 2026‑11‑15 — Versión 0.1.0 (fases 1–6 + base de 7 y 8)

### Entorno inspeccionado
Windows 11 Home 26300 · Visual Studio Enterprise 2026 (C++) · Git · JDK Temurin 25 · FFmpeg 9.0.2 · Node · Python 3.15 (sin ruedas para los motores de IA).
Instalado en esta sesión (con autorización): Flutter 3.50.0 stable en `%USERPROFILE%\dev\flutter`, Android SDK (cmdline‑tools, platform‑tools, android‑36, licencias aceptadas por el usuario), Python 3.12 (winget), dependencias del backend en `backend/.venv`.

### Funcionalidades completadas
- **Fase 1 – Base**: proyecto Flutter Android/iOS/Windows, navegación adaptable (barra lateral en escritorio, cajón en móvil) con las 11 secciones, SQLite con migraciones, configuración persistente, tema claro/oscuro.
- **Fase 2 – Smart Reader**: importación de PDF (pdfrx, con OCR en servidor para escaneados), imágenes (ML Kit en móvil / RapidOCR en Windows), XLSX, XLS (servidor), CSV, EML, HTML, enlaces web, chats de WhatsApp exportados (.txt/.zip), texto pegado, carpetas y arrastrar‑soltar (Windows), cámara/galería y "Compartir con Voice Studio" (Android). Lector frase a frase con resaltado, detección de idioma por frase, normalización de cantidades/medidas/fechas, diccionario técnico editable, marcadores, cola de lectura, progreso guardado, lectura de párrafo o página.
- **Fase 3 – Voice Recorder**: grabación manual AAC/M4A (WAV de respaldo), pausa/continuar, indicadores permanentes, guardar/descartar, reproducción con velocidad y búsqueda.
- **Fase 4 – Transcripción**: faster‑whisper en backend; en directo por WebSocket con segmentación por pausas y audio guardado; reconocedor del sistema en Android/iOS; transcripción de archivos WAV/MP3/M4A/AAC/FLAC/OGG.
- **Fase 5 – Diarización**: pyannote.audio (opcional), asignación de hablantes por solapamiento, renombrar, reasignar, dividir fragmentos, ajustar límites, sincronización tocar‑frase→saltar audio.
- **Fase 6 – Biblioteca**: búsqueda (título, notas y texto transcrito), etiquetas, favoritos, notas, orden por fecha/nombre/tipo/idioma/duración, exportación TXT/SRT/JSON/audio, borrado con audio.
- **Fase 7 (parcial)**: Excel, WhatsApp por importación autorizada, web, correo .eml.
- **Fase 8 (base)**: backend con autenticación (scrypt + JWT), sincronización con control de conflictos, historial de versiones, borrado sincronizado, subidas reanudables, borrado de cuenta; cliente con selección por elemento y almacenamiento seguro del token.
- Comandos de voz ES/EN por pulsar‑para‑hablar.

### Pendiente
- Verificar en un dispositivo Android real la lectura con la pantalla apagada, los controles de la pantalla de bloqueo y los botones Bluetooth (código y build listos; no probado en hardware).
- Controles multimedia del sistema en Windows (SMTC): `audio_service` no es compatible con Windows; allí la lectura continúa con la ventana minimizada pero sin controles en la barra de tareas.
- Gmail/Outlook por OAuth (necesita registrar la app; pasos en `ENGINES.md`).
- Resumen automático de documentos (la traducción ya está hecha; ver más abajo).
- Extensión "Compartir" de iOS (target de Xcode) y compilación iOS (requiere macOS).
- Fase 9: instaladores MSIX/Play, firma release, pruebas en dispositivos reales, perfilado de batería.

### Errores encontrados y resueltos
1. `flutter test` y carga de DLL de Python fallaban por la **ruta del proyecto demasiado larga** → se trabaja con `subst V:`; recomendado mover a ruta corta.
2. Ediciones con PowerShell 5.1 **corrompieron acentos** (UTF‑8 leído como ANSI) en 6 archivos → reparados con script y verificados por búsqueda.
3. `GET /engines` devolvía 500 porque `find_spec("pyannote.audio")` lanza si falta el paquete padre → corregido y cubierto por prueba.
4. `file_picker` 13 ya no acepta `allowMultiple` (siempre múltiple) → corregido.
5. Expectativa errónea en la prueba de WebSocket (duración) → corregida la prueba, no el código.
6. `pdfrx_engine 0.4.4` no compila con Dart 3.14; su versión nueva exige `archive 4`, incompatible con el paquete `excel` (archive 3) → `excel` sustituido por un lector XLSX propio (`lib/readers/xlsx_reader.dart`, con pruebas) y pdfrx actualizado a 2.12.
7. Plugins exigen `compileSdk 37` → configurado e instalada la plataforma android‑37.

### Pruebas realizadas
- `flutter analyze`: sin incidencias.
- `flutter test`: 32/32 (lector XLSX propio, detector de idioma, divisor de frases, normalizador, parser de comandos, WhatsApp, tablas, HTML, EML, cabecera WAV, exportaciones, repositorios SQLite en memoria, controlador de lectura con motor de voz simulado).
- `pytest`: 16/16 (salud, OpenAPI, transcripción + diarización con proveedores simulados, validaciones, TTS, WebSocket en directo, autenticación, sincronización con conflictos/historial/borrado/aislamiento entre usuarios, subida reanudable, borrado de cuenta, guarda de autenticación IA, solapamiento de hablantes, segmentador VAD, extracción CSV/HTML/PDF/XLSX, agrupación OCR, estado de motores reales).
- Prueba de humo real: servidor arrancado, `/health`, `/engines`, `/extract` (PDF real) y OCR real con RapidOCR sobre una imagen renderizada ("Instalar 12 cables THHN / Order 7: two panels" reconocido correctamente).
- **No verificado aún**: transcripción real con Whisper (requiere descargar el modelo, ≈460 MB), voces Piper (requiere descargar voces), pyannote (requiere token), ejecución en un dispositivo Android físico.

## 2026‑11‑15 — Reproducción en segundo plano (Android/iOS)

- `lib/player/reader_audio_handler.dart`: puente `audio_service` ↔ `ReaderController`. Notificación persistente y pantalla de bloqueo con título del documento, "Frase N de M" y la frase actual; botones anterior · repetir frase · reproducir/pausa · siguiente · detener. Botones de auriculares Bluetooth: play/pausa, siguiente/anterior, rebobinar = repetir frase, avance rápido = párrafo siguiente.
- Android: `MainActivity` hereda de `AudioServiceActivity`; servicio `mediaPlayback` en primer plano, receptor de botones multimedia, permisos `FOREGROUND_SERVICE(_MEDIA_PLAYBACK)`, `WAKE_LOCK`, `POST_NOTIFICATIONS` (se pide la primera vez que se pulsa reproducir). iOS: `UIBackgroundModes=audio` ya configurado.
- Error encontrado por las pruebas y corregido: `MediaItem` solo se compara por `id`, por lo que la pantalla de bloqueo no habría actualizado la frase actual.
- Pruebas: `flutter test` 34/34 (2 nuevas del puente multimedia), `flutter analyze` sin incidencias, APK debug compilado.

## 2026‑11‑15 — Traducción sin conexión ES↔EN

- **Motores**: Android/iOS → Google ML Kit Translation en el dispositivo (modelos ~30 MB por idioma, se descargan una vez tras confirmación del usuario). Windows → backend con modelos **Argos Translate ejecutados directamente sobre CTranslate2 + SentencePiece** (`ArgosCT2Provider`). Decisión: el paquete `argostranslate` arrastra PyTorch y spaCy (>1 GB); sus modelos son CTranslate2, que ya usa Whisper, así que solo se añade `sentencepiece`.
- **Seguridad de las instrucciones**: se traduce párrafo a párrafo; los párrafos que ya están en el idioma destino no se tocan; cada párrafo se marca si sus números (cantidades, medidas, fechas) difieren del original y la pantalla muestra un aviso y un filtro "Solo avisos".
- La traducción se guarda en `derived_texts` (`translation:en` / `translation:es`), separada del original; "Escuchar traducción" la lee como documento virtual sin modificar el original (sin marcadores ni progreso propios).
- Backend: `POST /api/v1/translate`, estado en `/engines`, `scripts/download_translation_models.py` (descarga los paquetes desde el índice de Argos: ≈400 MB en total).
- Pruebas: `flutter test` 40/40 (6 nuevas: números, párrafo a párrafo, idioma mixto, avisos, almacenamiento separado), `pytest` 19/19 (3 nuevas), APK debug compilado.
- **No verificado**: ML Kit en un dispositivo.

### Prueba real con modelos descargados (con autorización)
- Modelos instalados en `backend/data/translate`: es→en v1.9 (OPUS‑MT, **301 MB**) y en→es v1.0 (**92 MB**). La estimación previa de ~90 MB por par era incorrecta para es→en.
- Errores encontrados y corregidos:
  1. El servidor de modelos devuelve 403 al User‑Agent por defecto de Python → el script usa uno genérico y prueba los espejos del índice.
  2. El paquete es→en no usa SentencePiece sino **Moses + BPE de subword‑nmt** → añadido `_MosesBpeTokenizer` (`sacremoses`, `subword-nmt`, Python puro).
  3. Forzar `compute_type="int8"` hacía que es→en generase basura repetitiva → se usa la precisión propia del modelo.
  4. La destokenización dejaba "3 / 4" → normalizado a "3/4" (con prueba).
- Resultados (CPU, tras cargar el modelo): es→en ≈1 s para 3 párrafos, en→es ≈0,2 s.
  - "Mañana necesitamos comenzar la instalación del panel eléctrico." → "Tomorrow we need to start the installation of the electric panel." ✔
  - "Pasar 12 cables THHN por el tubo EMT de 3/4 de pulgada." → "Pass 12 THHN cables through the 3/4 inch EMT tube." ✔
  - "Pull two 12 AWG wires…" → "Tire dos cables AWG…" ✘ **se perdió el 12** → el aviso de números de la app marca este párrafo.
  - Términos técnicos: "conduit" → "drive", "breaker" → "break" (limitación del modelo genérico; el original se muestra siempre junto a la traducción).
- `pytest` 21/21 (incluye una prueba real es→en que se omite si el modelo no está descargado).

## 2026‑11‑15 — Protección de términos técnicos en la traducción

- `TermProtector` (`lib/services/translation/translation_service.dart`): antes de traducir sustituye los términos del **Diccionario técnico** (editable por el usuario) por marcadores opacos y los restaura después con la grafía original. Vale para ML Kit y para el backend.
- Elección del marcador **medida con los modelos reales**: `ZXQA`, `ZXQB`… se copian intactos en ambas direcciones; `[[0]]` y `__T0__` se destrozan ("0‑Passing", "_ _ T0 _ _").
- Si el motor pierde un marcador, el párrafo se marca con "Términos perdidos" (igual que el aviso de números) y se guarda en la traducción.
- "Breaker" añadido al diccionario por defecto (pronunciación "bréiker").
- Resultado real (backend + modelos Argos), antes → después:
  - "…por el conduit EMT…" → "…through the 3/4 inch **conduit EMT**." (antes "drive")
  - "Revisar el breaker de 20 amperios." → "Check the 20‑amp **breaker**." (antes "break")
  - "Pull two 12 AWG wires through the conduit and check the breaker." → "Tire dos cables AWG **12** a través de la conduit y compruebe el breaker." (antes se perdía el 12)
- Pruebas: `flutter test` 45/45 + 1 de integración real (`test/integration/real_translation_test.dart`, se omite si el backend no está en marcha; pasó con el backend real). APK debug compilado.
- Limitación: el diccionario se aplica a nuevas instalaciones; en una base de datos existente "Breaker" se añade desde *Diccionario técnico*.

## 2026‑11‑15 — Interfaz en inglés

- `lib/core/i18n.dart`: `tr('texto en español', [args])`. El texto español es la clave (código legible y respaldo garantizado); traducciones en `lib/core/i18n_en.dart` (~360 textos). Selector en *Configuración → Idioma de la interfaz*: Sistema / Español / Inglés; al cambiarlo se reconstruye toda la interfaz.
- Conversión asistida por script (analiza cadenas Dart, interpolaciones y literales adyacentes) y revisada a mano: se revirtieron falsos positivos (cabeceras HTTP, SQL, nombre de carpeta de datos, marcador `ZXQ…` de la protección de términos y las frases de prueba de voz, que deben sonar siempre en su idioma). Los mapas `const` de menú, estados de pedido y botón de pantalla de bloqueo pasaron a *getters* para no quedar congelados en el primer idioma.
- Se traducen también los mensajes de error que ve el usuario (importación, backend, grabación, sincronización). El contenido de los documentos, las etiquetas "Persona 1/2…" (requisito) y el texto que se genera para leer en voz alta no cambian.
- Pruebas nuevas (`test/i18n_test.dart`): todo `tr('…')` de `lib/` tiene traducción, los marcadores `{n}` coinciden y el cambio de idioma funciona; prueba de la pantalla de bloqueo en inglés. `flutter test` 49/49 (+1 de integración), análisis sin incidencias, APK compilado.
- **No verificado visualmente** (no hay dispositivo ni build de Windows): longitudes de texto en inglés en pantallas estrechas.

## 2026‑11‑15 — Primera ejecución en Windows ✅

- Modo de desarrollador activado por el usuario. Problemas resueltos para compilar:
  1. `flutter_tts` en Windows necesita **`nuget.exe`** (descarga C++/WinRT) → instalado con `winget install Microsoft.NuGet`.
  2. El primer intento fallido dejó en caché de CMake una ruta de instalación en `C:\Program Files` → se borró la caché de `build\windows` y compiló.
- `build\windows\x64\runner\Debug\voice_studio.exe` **compila, arranca y funciona**. Probado a mano en la app real:
  - Inicio, menú lateral con las 11 secciones, modo oscuro.
  - Importar → Pegar texto → documento guardado en SQLite con idioma detectado (ES).
  - Reproductor: lectura en voz alta con la voz del sistema de Windows, resaltado frase a frase (1/3 → 2/3 → 3/3) y vuelta al estado de reproducir al terminar.
  - Configuración → Idioma de la interfaz → Inglés: toda la interfaz cambia al instante.
- Aviso en el registro: el plugin `flutter_tts` envía un mensaje desde un hilo nativo no permitido en Windows. Es un fallo del plugin; no impidió la lectura, pero puede causar inestabilidad. Seguimiento pendiente (actualizar el plugin o usar el backend con Piper).
### Pruebas manuales en Windows (app real + backend real, Whisper `base` en CPU)

| Función | Resultado |
|---|---|
| Grabar: iniciar, pausa/continuar, finalizar y guardar, descartar | ✅ (indicadores, contador, tamaño de archivo; la barra de nivel se mueve con la voz) |
| Transcribir la grabación guardada | ✅ "Please check the breaker on the second door and label each circuit." (dijo "floor"; micrófono captando altavoz) |
| Diálogo de consentimiento antes de enviar audio al backend | ✅ (indica backend local) |
| Tocar una frase → el audio salta a ese momento | ✅ |
| Transcripción en directo | ✅ tras corregir el VAD (ver abajo): "Tomorrow, we start the installation at 7 in the morning." / "Do we have all the materials for the panel?" |
| Selector de archivos nativo, selección múltiple | ✅ |
| Imagen → OCR (RapidOCR vía backend) | ✅ "Orden 9: instalar 4 breakers de 20 A" / "Revisar el conduit EMT" |
| PDF → texto en el PC (pdfrx) con número de página | ✅ |
| Importar audio y transcribir | ✅ |
| Buscar una palabra en todas las transcripciones | ✅ |
| Persistencia tras reiniciar la app | ✅ |
| Arrastrar y soltar | ⚠ No probado (la automatización no puede arrastrar desde el Explorador) |

### Errores encontrados en estas pruebas y corregidos
1. **Whisper con `device=auto` elegía la GPU NVIDIA sin las librerías CUDA** (`cublas64_12.dll`) → error 500. Ahora vuelve automáticamente a CPU (con prueba).
2. **Sin pyannote, la diarización importaba `torch` antes de comprobar la instalación** → error 500 en toda transcripción. Ahora devuelve "no disponible" y se transcribe con un hablante (con prueba usando el proveedor real).
3. **Marcas de tiempo de Whisper más allá del final del audio** (14,1 s en un audio de 8,7 s) → se recortan a la duración real.
4. **La transcripción en directo perdía palabras** ("Tomorrow", "morning", "Do we have all the materials"): el detector de voz tenía un umbral fijo y el micrófono real capta bajo (media −50 dBFS, picos −24 dBFS). Ahora el umbral se adapta al ruido de fondo, con histéresis y 500 ms de margen inicial. Prueba de regresión con niveles medidos del micrófono real.
5. Robustez añadida: si el micrófono no respeta 16 kHz mono (Windows puede adaptar el formato al dispositivo), el cliente escucha `onConfigChanged`, guarda el WAV con su formato real y envía al servidor audio convertido a 16 kHz mono (`PcmConverter`, con pruebas). En este equipo el micrófono sí entregó 16 kHz mono (comprobado con ffprobe).

Pruebas: `flutter test` 54/54, `pytest` 24/24.

## 2026‑11‑15 — Versión descargable 0.1.0 (GitHub Releases)

- Publicada en https://github.com/anthonylol12/VoiceStudio/releases/tag/v0.1.0: APK Android arm64 (56 MB), arm32 (43 MB), x86_64 (59 MB), universal (152 MB) y ZIP de Windows x64 (18 MB, incluye las DLL redistribuibles de Visual C++ y LEEME.txt).
- Errores corregidos al compilar las versiones finales:
  1. R8 fallaba por clases opcionales de ML Kit (OCR chino/japonés/coreano/devanagari) → `android/app/proguard-rules.pro`.
  2. La APK final bloqueaba `http://`, así que el teléfono no podía usar el backend del PC por Wi‑Fi (solo funcionaba en la versión de depuración) → se permite `http` y Configuración muestra un aviso si la URL es `http` a un servidor fuera de la red local (`isInsecureRemoteUrl`, con pruebas).
- Verificado: firma de las 4 APK (`apksigner`), manifiesto (`usesCleartextTraffic=true`, permisos, minSdk 24), ZIP descomprimido en una carpeta nueva → la app abre, carga datos, graba y guarda, y muestra el aviso de `http`; integridad SHA‑256 de las descargas desde GitHub.
- APK firmadas con la clave de depuración de este PC (pendiente: clave de publicación propia). No probadas en un teléfono real.

### Compilación
- **Android (debug)**: ✅ `build\app\outputs\flutter-apk\app-debug.apk` (222 MB, debug sin reducir) compilado tras trasladar el proyecto a una ruta corta (`%USERPROFILE%\dev\VoiceStudio`). Aún no instalado en un dispositivo.
- Tras el traslado: `flutter analyze` sin incidencias, `flutter test` 32/32, `pytest` 16/16 con el venv recreado.
- **Windows**: bloqueada por el **Modo de desarrollador** de Windows (Flutter necesita enlaces simbólicos). El valor `AllowDevelopmentWithoutDevLicense` no estaba en el registro al comprobarlo.
- **iOS**: requiere macOS/Xcode; proyecto y permisos preparados.
- Al trasladar se eliminaron solo carpetas regenerables (`build`, `.dart_tool`, `backend/.venv`, `backend/data`): ejecutar `flutter pub get` y recrear el venv (`backend\run_server.ps1` lo hace).
