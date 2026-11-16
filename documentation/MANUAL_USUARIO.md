# Voice Studio — Manual de uso

Voice Studio lee en voz alta documentos y órdenes de trabajo, graba conversaciones, las transcribe (también en directo) y separa a quién habla. Está pensado para trabajar con las manos ocupadas.

Este manual cubre el **ordenador (Windows)** y el **teléfono (Android)**. Las diferencias entre ambos se indican con 🖥️ (PC) y 📱 (teléfono).

---

## Índice

1. [Qué funciona sin conexión y qué necesita el servidor](#1-qué-funciona-sin-conexión-y-qué-necesita-el-servidor)
2. [Instalación en el PC (Windows)](#2-instalación-en-el-pc-windows)
3. [Instalación en el teléfono (Android)](#3-instalación-en-el-teléfono-android)
4. [Primeros pasos](#4-primeros-pasos)
5. [Importar documentos](#5-importar-documentos)
6. [Escuchar un documento (Reproductor)](#6-escuchar-un-documento-reproductor)
7. [Comandos de voz](#7-comandos-de-voz)
8. [Pedidos (órdenes de trabajo)](#8-pedidos-órdenes-de-trabajo)
9. [Grabar una conversación](#9-grabar-una-conversación)
10. [Transcripción en directo](#10-transcripción-en-directo)
11. [Transcripciones y biblioteca](#11-transcripciones-y-biblioteca)
12. [Traducir un documento](#12-traducir-un-documento)
13. [Diccionario técnico](#13-diccionario-técnico)
14. [Sincronización con la nube (opcional)](#14-sincronización-con-la-nube-opcional)
15. [Configuración](#15-configuración)
16. [Privacidad](#16-privacidad)
17. [Solución de problemas](#17-solución-de-problemas)

---

## 1. Qué funciona sin conexión y qué necesita el servidor

Voice Studio tiene dos partes:

- **La app** (PC o teléfono): guarda todo en el propio dispositivo y funciona sin Internet.
- **El backend** (servidor de IA): un programa que se ejecuta en tu PC y hace las tareas pesadas (Whisper, OCR en Windows, voces Piper y traducción en el PC). El teléfono puede usar el backend de tu PC a través de la red Wi‑Fi.

| Función | 🖥️ PC | 📱 Teléfono |
|---|---|---|
| Leer documentos en voz alta (voz del sistema) | Sin conexión | Sin conexión |
| Importar PDF, Excel, CSV, texto, correos .eml, chats | Sin conexión | Sin conexión |
| Fotos → texto (OCR) | Necesita el backend | Sin conexión (en el teléfono) |
| PDF escaneado (sin texto) | Necesita el backend | Necesita el backend |
| Grabar audio | Sin conexión | Sin conexión |
| Transcribir grabaciones y archivos de audio | Necesita el backend | Necesita el backend |
| Transcripción en directo | Necesita el backend | Backend **o** reconocedor del teléfono (sin audio guardado) |
| Separar hablantes automáticamente | Backend + pyannote (opcional) | Backend + pyannote (opcional) |
| Traducir español ↔ inglés | Backend con modelos descargados | Sin conexión (tras descargar ~30 MB por idioma) |
| Voces neuronales Piper | Necesita el backend | Necesita el backend |
| Sincronizar con la nube | Necesita un servidor y cuenta | Necesita un servidor y cuenta |

---

## 2. Instalación en el PC (Windows)

### 2.1 Descargar e instalar

1. Entra en **[Descargas (Releases)](https://github.com/anthonylol12/VoiceStudio/releases/latest)** y descarga `VoiceStudio-0.1.0-windows-x64.zip` (Windows 10/11 de 64 bits, ~18 MB).
2. **Descomprímelo** (clic derecho → *Extraer todo*) en una carpeta, por ejemplo `C:\Programas\VoiceStudio`. No lo abras desde dentro del ZIP.
3. Abre `voice_studio.exe`. Si aparece *"Windows protegió su PC"*, pulsa **Más información → Ejecutar de todas formas** (la app no está firmada con un certificado de pago).
4. Opcional: clic derecho en `voice_studio.exe` → *Enviar a → Escritorio (crear acceso directo)*.

Mantén todos los archivos de la carpeta juntos. Tus datos se guardan en `%APPDATA%\com.voicestudio`, no en esa carpeta, así que puedes reemplazarla al actualizar sin perder nada.

### 2.2 Requisitos del backend (solo si vas a transcribir, hacer OCR o traducir en el PC)

- Python 3.12 y FFmpeg.
- El código del proyecto: descarga el *Source code (zip)* desde la misma página de Releases o clona el repositorio.

> ¿Prefieres compilar la app tú mismo? Ver [BUILD.md](BUILD.md) (Flutter, Visual Studio con C++, NuGet y Modo de desarrollador).

### 2.3 Arrancar el backend (para transcribir, OCR y traducir)

En PowerShell, dentro de la carpeta del proyecto:

```powershell
cd backend
.\run_server.ps1
```

- La primera vez crea el entorno e instala las dependencias (puede tardar varios minutos).
- La **primera transcripción** descarga el modelo Whisper (`small`, unos 460 MB). Después funciona sin Internet.
- Deja esa ventana abierta mientras uses la app. Para pararlo, pulsa `Ctrl+C`.

Opcional:

```powershell
# Voces neuronales Piper (español e inglés, ~120 MB)
.\.venv\Scripts\python.exe scripts\download_piper_voices.py

# Modelos de traducción sin conexión (~400 MB)
.\.venv\Scripts\python.exe scripts\download_translation_models.py
```

### 2.4 Comprobar la conexión

En la app: **Configuración → Backend de IA → Guardar y probar conexión**. Verás qué motores están disponibles (✔) y cuáles no (✘), con el motivo.

---

## 3. Instalación en el teléfono (Android)

### 3.1 Descargar e instalar

1. Desde el teléfono, entra en **[Descargas (Releases)](https://github.com/anthonylol12/VoiceStudio/releases/latest)** y descarga:
   - `VoiceStudio-0.1.0-android-arm64.apk` → casi todos los teléfonos de los últimos años (~56 MB).
   - `VoiceStudio-0.1.0-android-arm32.apk` → teléfonos antiguos de 32 bits.
   - `VoiceStudio-0.1.0-android-universal.apk` → si no sabes cuál o el anterior no se instala (~152 MB, sirve para todos).
2. Abre el archivo descargado. Android pedirá permitir **"Instalar apps desconocidas"** para el navegador o el gestor de archivos: actívalo y vuelve atrás.
3. Pulsa **Instalar**. Si Play Protect avisa de que la app no es conocida, elige **"Instalar de todas formas"** (no está publicada en Google Play).

Requiere Android 7.0 o superior.

> También puedes compilarla e instalarla por USB desde el PC: ver [BUILD.md](BUILD.md).

### 3.2 Permisos

Android pedirá permisos la primera vez que los necesites:

- **Micrófono**: solo al pulsar *Grabar*, *Comenzar transcripción* o el botón de comando de voz.
- **Notificaciones**: la primera vez que pulses *Reproducir* (para la notificación de lectura).
- **Cámara / fotos**: al importar una foto.

### 3.3 Usar el backend del PC desde el teléfono

1. En el PC, arranca el backend para la red local:
   ```powershell
   cd backend
   .\run_server.ps1 -Lan
   ```
   Si Windows pregunta por el Firewall, permite el acceso en **redes privadas**.
2. Averigua la IP del PC: `ipconfig` → *Dirección IPv4* (por ejemplo `192.168.1.20`).
3. En el teléfono (misma Wi‑Fi): **Configuración → URL del backend** → `http://192.168.1.20:8765` → *Guardar y probar conexión*.
4. Recomendado: en `backend\.env` pon `VS_REQUIRE_AUTH_FOR_AI=true` para que solo usuarios con sesión puedan usar el servidor.

> `http://` está bien dentro de tu red de casa o del trabajo. Si algún día usas un servidor **fuera** de tu red, usa `https://`: la app muestra un aviso en rojo si escribes una dirección `http://` pública.
>
> Sin el backend también funcionan: leer, grabar, OCR de fotos, traducción y la transcripción en directo con el **reconocedor del dispositivo**.

### 3.4 iPhone

El proyecto está preparado para iOS, pero hay que compilarlo en un Mac con Xcode (ver [BUILD.md](BUILD.md)).

---

## 4. Primeros pasos

Al abrir la app verás **Inicio** con accesos rápidos:

- **Grabar** — empezar a grabar una conversación.
- **Importar documento** — añadir un PDF, foto, Excel, texto…
- **Transcribir en directo** — ver el texto mientras la gente habla.
- **Continuar: …** — retomar el último documento donde lo dejaste.

Más abajo: estado de sincronización, documentos recientes y grabaciones recientes.

**Navegación:**
- 🖥️ Menú lateral a la izquierda con todas las secciones (se compacta si la ventana es estrecha).
- 📱 Botón ☰ arriba a la izquierda para abrir el menú.

Recomendación al empezar: **Configuración → Voz y lectura → Probar voz** (Español / English) para comprobar que se oye bien.

---

## 5. Importar documentos

Ve a **Documentos → Importar** (o *Importar documento* en Inicio).

| Opción | 🖥️ PC | 📱 Teléfono |
|---|---|---|
| **Archivos** — PDF, imágenes (JPG, PNG, WEBP), Excel (XLSX, XLS), CSV, TXT, correo `.eml`, chat de WhatsApp `.txt`/`.zip` | ✔ (puedes elegir varios) | ✔ |
| **Importar carpeta** — importa todos los archivos compatibles de una carpeta | ✔ | — |
| **Arrastrar y soltar** archivos o carpetas sobre la sección Documentos | ✔ | — |
| **Cámara (OCR)** — foto de una orden de trabajo | — | ✔ |
| **Galería / capturas (OCR)** | — | ✔ |
| **Página web (enlace)** — extrae el contenido principal | ✔ | ✔ |
| **Pegar texto** — mensajes, notas, órdenes copiadas | ✔ | ✔ |
| **Compartir con Voice Studio** desde WhatsApp, correo, navegador o archivos | — | ✔ |

Consejos:
- **WhatsApp**: en el chat, *⋮ → Más → Exportar chat* y elige Voice Studio (o guarda el `.txt`/`.zip` e impórtalo). Cada mensaje se lee con su autor y hora.
- **Correo**: guarda el mensaje como `.eml` (Gmail: *⋮ → Descargar mensaje*; Outlook: arrastrar el mensaje a una carpeta) o compártelo con la app en el teléfono.
- **Excel**: si la primera fila tiene encabezados, cada fila se lee como *"Material: Cable THHN; Cantidad: 500"*.

En la lista de documentos, el menú **⋮** de cada uno permite: *Añadir a la cola*, *Marcar como pedido*, *Favorito*, *Sincronizar con la nube*, *Cambiar nombre* y *Eliminar*. El buscador busca en títulos **y** en el contenido.

---

## 6. Escuchar un documento (Reproductor)

Toca un documento para abrirlo en el **Reproductor**. La frase que se está leyendo aparece resaltada.

### Controles

| Botón | Acción |
|---|---|
| ⏯ (grande) | Reproducir / pausar |
| ⏹ | Detener |
| ⏮ / ⏭ | Frase anterior / siguiente |
| ↻ | Repetir la frase actual |
| ⏫ / ⏬ | Párrafo anterior / siguiente |
| 🎤 | Comando de voz (ver sección 7) |
| 0.75x … 2.0x | Velocidad |
| Auto / ES / EN | Idioma de lectura (Auto detecta el idioma de cada frase) |
| 🔊 deslizador | Volumen |
| Voz local / Voz Piper | Motor de voz (Piper necesita el backend) |

Más:
- **Toca una frase** para leer desde ahí.
- **Mantén pulsado un párrafo** para leer solo ese párrafo.
- 📄 **Leer página** (en PDFs de varias páginas): lee solo la página elegida.
- 🔖 **Guardar marcador** y 📑 **Marcadores** para volver a un punto.
- El progreso se guarda solo: al volver al documento continúa donde lo dejaste.
- **Cola de lectura**: añade documentos desde su menú ⋮ y pulsa *Reproducir siguiente* en Documentos.
- Abajo verás un **mini reproductor** en cualquier sección mientras haya un documento cargado.

📱 **En el teléfono la lectura sigue con la pantalla apagada.** Tienes controles en la **pantalla de bloqueo** y en la **notificación**, y funcionan los **botones de auriculares Bluetooth**:
- Play/Pausa, Siguiente, Anterior.
- Rebobinar = repetir frase · Avance rápido = siguiente párrafo.

La app lee bien cantidades y medidas: `3/4"` → "tres cuartos de pulgada", `10 ft` → "10 pies", `15/11/2026` → "15 de noviembre de 2026", `20A` → "20 amperios". **El texto que ves nunca se modifica**; solo cambia cómo se pronuncia.

---

## 7. Comandos de voz

En el Reproductor, pulsa el botón 🎤 y di un comando corto. El micrófono **solo se activa al pulsar el botón** (no hay escucha continua, para evitar activaciones accidentales en lugares ruidosos).

| Di (español) | Di (inglés) | Hace |
|---|---|---|
| "Pausa" | "Pause" | Pausa |
| "Continúa" | "Continue" / "Resume" | Continúa |
| "Repite" | "Repeat" | Repite la frase |
| "Más despacio" | "Slower" | Baja la velocidad |
| "Más rápido" | "Faster" | Sube la velocidad |
| "Siguiente" | "Next" | Frase siguiente |
| "Vuelve atrás" / "Anterior" | "Go back" / "Previous" | Frase anterior |
| "Leer en inglés" | "Read in English" | Fuerza el inglés |
| "Leer en español" | "Read in Spanish" | Fuerza el español |
| "Detener lectura" / "Para" | "Stop" | Detiene |

- 📱 Usa el reconocimiento de voz del teléfono.
- 🖥️ Graba 2,5 segundos y los envía al backend (necesita el backend en marcha).
- Se ignoran frases largas: solo se aceptan comandos de pocas palabras.

---

## 8. Pedidos (órdenes de trabajo)

Marca un documento como pedido desde su menú **⋮ → Marcar como pedido**. En la sección **Pedidos** se agrupan por estado: **Pendiente**, **En curso** y **Completado**. Cambia el estado con el desplegable de cada pedido. Toca el pedido para escucharlo.

---

## 9. Grabar una conversación

Ve a **Grabar conversación**.

1. Pulsa **Iniciar grabación**. Siempre verás: indicador *GRABANDO*, duración, estado del micrófono, nivel de audio y tamaño del archivo.
2. **Pausar / Continuar** cuando lo necesites.
3. **Finalizar y guardar**: escribe un nombre (o deja el propuesto).
4. En el aviso *Grabación guardada* puedes **Abrir** o **Transcribir** directamente.
5. **Descartar** borra la toma actual (pide confirmación).

Las grabaciones se guardan solo en tu dispositivo. **Informa a las personas presentes y obtén su consentimiento antes de grabar**, según la ley aplicable.

---

## 10. Transcripción en directo

Ve a **Transcripción en directo**.

1. Elige el idioma: **Detectar idioma**, **Español** o **English**.
2. 📱 Elige el motor:
   - **Whisper (backend) + audio + hablantes**: más preciso, guarda el audio y permite separar hablantes. Necesita el backend.
   - **Reconocedor del dispositivo (sin audio)**: funciona sin el PC, pero no guarda el audio.
3. Pulsa **Comenzar transcripción**. El texto aparece por frases, con la hora y "Persona 1, Persona 2…".
4. Pulsa **Detener y guardar**. Se abre la transcripción guardada.

🖥️ En el PC se usa siempre el backend (inícialo antes, ver 2.3).

Si el backend tiene **pyannote** configurado, al terminar se reasignan los hablantes automáticamente. Si no, todo queda como *Persona 1* y puedes corregirlo a mano (sección 11).

---

## 11. Transcripciones y biblioteca

### Transcripciones

- **Transcribir audio**: importa archivos WAV, MP3, M4A, AAC, FLAC u OGG y elige *Importar y transcribir* (o *Solo importar*).
- El buscador busca **palabras dentro de todas las transcripciones**.
- Al final de la lista aparecen las *Grabaciones sin transcribir*.

### Dentro de una transcripción

- Barra de audio arriba: reproducir/pausar, detener, posición y **velocidad**.
- **Toca una frase** → el audio salta a ese momento. La frase que suena se resalta.
- Chips de hablantes (**Persona 1**…): tócalos para **cambiar el nombre** (p. ej. "Carlos").
- Menú **⋮** de cada frase:
  - **Corregir texto, hablante o límites** (inicio y fin en segundos, o asignarla a otro hablante o a uno nuevo).
  - **Dividir aquí** (en la posición actual del audio).
- Las frases corregidas se marcan como *editado*.
- Menú **⋮** superior: *Cambiar nombre*, *Notas*, *Etiquetas*, *Sincronizar con la nube*, *Volver a transcribir*, **Exportar** (.txt, subtítulos .srt, datos .json o el audio) y *Eliminar*.
- ☆ para marcar como favorito.

### Biblioteca de grabaciones

Lista todas las grabaciones con filtros:
- **Ordenar** por fecha, nombre, tipo, idioma o duración.
- **Favoritos** y **#etiquetas**.
- Buscador por nombre, notas o palabras de la transcripción.
- 🎤 para grabar y 🎵 para importar audio.

---

## 12. Traducir un documento

En el Reproductor, pulsa el botón de **traducir** (文A).

1. Elige **Al inglés** o **Al español** y pulsa **Traducir**.
   - 📱 La primera vez pide permiso para descargar los modelos de Google (~30 MB por idioma). Después traduce sin Internet.
   - 🖥️ Necesita el backend y los modelos de traducción (ver 2.3).
2. Verás cada párrafo traducido con el **original debajo**. **El documento original nunca se modifica**; la traducción se guarda aparte.
3. **Avisos de seguridad**: si un párrafo traducido tiene **números distintos** al original (cantidades, medidas, fechas) o pierde un **término técnico**, se marca con ⚠. Usa *Solo avisos* para revisar solo esos párrafos.
4. **Escuchar traducción** la lee en voz alta.

Los términos del Diccionario técnico (EMT, THHN, conduit, breaker…) se mantienen sin traducir.

---

## 13. Diccionario técnico

Sirve para que siglas y términos se **pronuncien bien** y para que **no se traduzcan**.

- Ya incluye: EMT, THHN, PVC, AWG, GFCI, Conduit, Romex, Electrical panel, Circuit breaker, Breaker, Feeder.
- **Añadir término**: escribe el término tal como aparece (p. ej. `THHN`) y cómo debe sonar en español y en inglés. Usa **Probar ES / Probar EN** para oírlo.
- **Distinguir mayúsculas**: actívalo para siglas (así "EMT" no afecta a palabras como "emt…").
- Toca un término para editarlo y usa 🗑 para eliminarlo.

---

## 14. Sincronización con la nube (opcional)

Sin cuenta, todo funciona en local. Si tienes un servidor Voice Studio:

1. **Sincronización** → escribe correo y contraseña (mínimo 10 caracteres) → **Crear cuenta** o **Iniciar sesión**.
2. Marca qué se sincroniza: interruptor por documento y por grabación, o desde el menú ⋮ de cada uno (*Sincronizar con la nube*). **Solo se envía lo que marques.**
3. **Subir también los archivos de audio** (opcional): sube por bloques y se reanuda si se corta la conexión.
4. **Sincronizar ahora**.

Si el mismo elemento se cambió en dos dispositivos, nada se sobrescribe sin avisar: la versión del servidor se guarda como copia aparte *"(versión del servidor)"*.

**Eliminar cuenta y datos del servidor** borra la cuenta y todo lo sincronizado (los datos locales se conservan).

---

## 15. Configuración

- **Apariencia**: Sistema / Claro / Oscuro.
- **Idioma de la interfaz**: Sistema / Español / Inglés.
- **Voz y lectura**:
  - Motor local o Piper/nube.
  - Voz preferida para español y para inglés.
  - Probar voz.
  - Activar los comandos de voz.
- **Backend de IA**:
  - URL del servidor, *Guardar y probar conexión* y estado de cada motor.
  - Separar hablantes al transcribir.
  - Permiso para enviar audio y documentos al backend.
- **Datos**:
  - Ubicación de los datos locales.
  - **Eliminar todos los datos locales** (no se puede deshacer).

---

## 16. Privacidad

- El micrófono **solo** se activa cuando tú pulsas un botón (Grabar, Transcripción en directo o 🎤). No hay grabaciones ocultas ni escucha automática.
- Antes de enviar audio o documentos al backend por primera vez, la app **pide permiso** e indica si el servidor está en tu propio PC o es remoto.
- Nada se sube a la nube si no lo marcas tú.
- Los hablantes se identifican solo como "Persona 1, 2…". No hay reconocimiento biométrico.
- Cumple la ley aplicable y pide consentimiento antes de grabar a otras personas.

---

## 17. Solución de problemas

| Problema | Solución |
|---|---|
| "No se pudo conectar con el backend" | Arranca `backend\run_server.ps1` (o `-Lan` para el teléfono). Comprueba la URL en Configuración y pulsa *Guardar y probar conexión*. |
| 📱 El teléfono no conecta con el PC | Misma Wi‑Fi. Usa la IP del PC (no `127.0.0.1`). Permite Python en el Firewall de Windows (redes privadas). |
| La primera transcripción tarda mucho | Se está descargando el modelo Whisper (~460 MB). Las siguientes son rápidas. |
| "Separar hablantes: no disponible" | Es opcional: instala pyannote y configura `VS_HF_TOKEN` (ver [ENGINES.md](ENGINES.md)). Mientras tanto, corrige los hablantes a mano. |
| No se oye la lectura | Sube el volumen del sistema y el deslizador 🔊. En Configuración prueba otra voz o el motor local. |
| Piper: "Sin voces" | Ejecuta `scripts\download_piper_voices.py` en el backend. |
| Traducción en PC: "No hay modelo" | Ejecuta `scripts\download_translation_models.py` en el backend. |
| 📱 No aparece la notificación de lectura | Permite las notificaciones de Voice Studio en los ajustes de Android. |
| 🖥️ No compila: "symlink support" | Activa el Modo de desarrollador de Windows. |
| 🖥️ No compila: "nuget.exe not found" | `winget install Microsoft.NuGet` y borra `build\windows` antes de reintentar. |
| Permiso de micrófono denegado | Actívalo en los ajustes de privacidad del sistema (Windows: *Privacidad → Micrófono*; Android: *Ajustes → Apps → Voice Studio → Permisos*). |
