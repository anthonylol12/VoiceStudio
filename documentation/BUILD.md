# Instalación y compilación

## Requisitos

| Herramienta | Versión usada | Para |
|---|---|---|
| Flutter SDK | 3.50.0 (Dart 3.14) | App |
| Visual Studio 2022/2026 con "Desarrollo para el escritorio con C++" | 2026 Enterprise 18.12 | Windows |
| Android SDK (platform 36, build‑tools 36) + JDK 17–25 | JDK Temurin 25 | Android |
| Xcode 16+ en macOS | — | iOS |
| Python | 3.12 (los motores de IA aún no publican ruedas para 3.15) | Backend |
| FFmpeg | 9.0 | Conversión de audio |

**Windows:** activa *Configuración → Sistema → Para programadores → Modo de desarrollador* (Flutter necesita enlaces simbólicos para los plugins) e instala NuGet (`winget install Microsoft.NuGet`; lo necesita el plugin de voz `flutter_tts`). Si una compilación falló antes de instalar NuGet, borra `build\windows` antes de reintentar (la caché de CMake guarda una ruta de instalación incorrecta).

**Rutas largas:** coloca el proyecto en una ruta corta (p. ej. `C:\dev\VoiceStudio`). Con rutas de más de ~200 caracteres fallan la compilación de shaders de Flutter y la carga de DLL de Python (onnxruntime, PyAV). Alternativa temporal: `subst V: "C:\ruta\larga\VoiceStudio"` y trabajar desde `V:\`.

## App Flutter

```powershell
flutter pub get
flutter analyze
flutter test
flutter run -d windows                 # desarrollo
flutter build windows --release        # build\windows\x64\runner\Release\voice_studio.exe
flutter build apk --release            # build\app\outputs\flutter-apk\app-release.apk
flutter build appbundle --release      # Google Play
```

Android release: crea una clave (`keytool -genkey -v -keystore voice-studio.jks -keyalg RSA -keysize 2048 -validity 10000 -alias voicestudio`), un `android/key.properties` y configura `signingConfigs` en `android/app/build.gradle.kts` (hoy la build release usa la firma de depuración). La build *debug* permite HTTP en la red local; la *release* exige HTTPS.

iOS (en un Mac): `cd ios && pod install`, abrir `Runner.xcworkspace`, elegir equipo de firma, `flutter build ipa`. Los textos de permisos (micrófono, voz, cámara, fotos) ya están en `Info.plist`. La extensión "Compartir" de iOS necesita un *Share Extension target* en Xcode con un App Group (ver documentación de `receive_sharing_intent`).

## Backend

```powershell
cd backend
py -3.12 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements-ai.txt   # o requirements.txt sin motores de IA
copy .env.example .env                                             # y edita VS_SECRET_KEY
.\.venv\Scripts\python.exe -m pytest
.\.venv\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8765
```
- Swagger/OpenAPI: <http://127.0.0.1:8765/docs> · <http://127.0.0.1:8765/openapi.json>
- Para usarlo desde un móvil Android en la misma red: `.\run_server.ps1 -Lan`, `VS_REQUIRE_AUTH_FOR_AI=true` y en la app *Configuración → URL del backend* `http://IP-DEL-PC:8765`. Permite el puerto 8765 en el Firewall de Windows.
- PostgreSQL: `VS_DATABASE_URL=postgresql+psycopg://usuario:clave@host:5432/voicestudio` (las tablas se crean al arrancar).

## Distribución (pendiente — fase 9)

- Windows: empaquetar `build\windows\x64\runner\Release` con MSIX (`msix` de pub.dev) o Inno Setup; incluir el backend como servicio opcional (PyInstaller).
- Android: Play Console con App Bundle firmado.
