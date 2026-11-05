# Práctica 4: Gestión de archivos multiplataforma (Android e iOS)

IPN · Escuela Superior de Cómputo · Desarrollo de aplicaciones móviles nativas

## 1. Introducción

Se desarrollaron dos aplicaciones con **Flutter (Dart)**, ambas con objetivos Android e iOS y 100 % funcionales sin conexión:

| Parte | Carpeta | Descripción |
|---|---|---|
| 1 | `parte1_gestor_archivos/` | Gestor de archivos: explora el espacio propio de la app y carpetas/archivos elegidos con el selector del sistema; visores de texto, JSON/XML con resaltado, imágenes con zoom y rotación; metadatos, recientes, favoritos, caché de miniaturas, copiar/mover/renombrar/eliminar. |
| 2 | `parte2_juego/` | **Apagón**, juego de puzzle original (tablero de luces) con 2 niveles (3x3 y 5x5), puntuación, progreso, efectos visuales/sonido/vibración y guardado/carga en **TXT, XML y JSON**. |

Ambas incluyen los temas **Guinda (IPN)** y **Azul (ESCOM)**, con modo claro/oscuro automático según el sistema.

## 2. Versiones y dependencias

| Elemento | Versión |
|---|---|
| Flutter / Dart | 3.47.2 / 3.13.2 |
| Android mínimo / objetivo | API 24 (Android 7.0) / `flutter.targetSdkVersion` |
| iOS mínimo | iOS 15 (ver §6) |
| Paquetes | `path_provider`, `file_picker`, `shared_preferences`, `share_plus`, `path`, `xml`; Parte 1 además `mime`, `open_filex` |

Sin permisos de almacenamiento global: no se declara `READ/WRITE_EXTERNAL_STORAGE` ni `MANAGE_EXTERNAL_STORAGE`.

## 3. Compilación y ejecución

### Android (Windows/macOS/Linux)
```bash
cd parte1_gestor_archivos   # o parte2_juego
flutter pub get
flutter run                 # emulador o dispositivo con depuración USB
flutter build apk --debug   # build/app/outputs/flutter-apk/app-debug.apk
```

### iOS (requiere macOS + Xcode 15+)
```bash
cd parte1_gestor_archivos   # o parte2_juego
flutter pub get
cd ios && pod install && cd ..
open ios/Runner.xcworkspace   # Signing & Capabilities: elegir Team; Deployment Target = 15.0
flutter run -d <simulador-o-iPhone>
```
Preparación de Xcode: instalar Xcode y *Command Line Tools*, aceptar licencia (`sudo xcodebuild -license`), `sudo gem install cocoapods` (o `brew install cocoapods`), abrir un simulador (`open -a Simulator`) y comprobar con `flutter doctor`.
En `ios/Runner/Info.plist` de ambas apps se añadieron `UIFileSharingEnabled` y `LSSupportsOpeningDocumentsInPlace` para que el sandbox de la app sea visible en la app *Files*.

## 4. Arquitectura e implementación

### Código compartido
Toda la lógica y la UI están en Dart (un único código para ambos sistemas). No fue necesario código nativo propio; las diferencias de plataforma las resuelven los plugins:

| Necesidad | API | Android | iOS |
|---|---|---|---|
| Espacio privado | `path_provider` | `filesDir` / `cacheDir` | `Documents` / `Caches` del sandbox |
| Selector de archivos/carpetas | `file_picker` | Storage Access Framework (`ACTION_OPEN_DOCUMENT(_TREE)`) | `UIDocumentPickerViewController` |
| Exportar | `FilePicker.saveFile` | `ACTION_CREATE_DOCUMENT` | Document picker (exportar) |
| Compartir | `share_plus` | `Intent.ACTION_SEND` | `UIActivityViewController` |
| Abrir con otra app | `open_filex` | `Intent.ACTION_VIEW` | `UIDocumentInteractionController` |
| Preferencias (tema, recientes, favoritos, opciones) | `shared_preferences` | `SharedPreferences` | `NSUserDefaults` |

### Parte 1 – `parte1_gestor_archivos/lib`
* `main.dart` – arranque, temas, siembra de archivos de ejemplo.
* `home.dart` – navegación responsiva (`NavigationBar` en vertical, `NavigationRail` en pantallas ≥ 700 dp), raíces autorizadas, navegador con *breadcrumbs*, operaciones de archivo, diálogo de formatos no soportados.
* `viewers.dart` – visor de texto, resaltado propio de JSON y XML (formateo con `jsonEncode(indent)` y `xml`), visor de imágenes (`InteractiveViewer` + rotación), metadatos (indica *No disponible* cuando falta un dato, p. ej. fecha de creación).
* `storage.dart` – `Prefs` (persistencia) y `ThumbCache` (miniaturas en memoria y disco, la clave incluye ruta+tamaño+fecha para invalidarse sola).

Seguridad: el acceso a carpetas/archivos externos sólo ocurre tras un diálogo que explica la finalidad y mediante el selector del sistema; si se cancela se respeta. Antes de escribir se valida el destino (archivo de prueba), se confirman las acciones destructivas y se capturan errores de ruta inexistente, permiso revocado, lectura fallida y almacenamiento lleno (errno 28) sin bloquear la app.

### Parte 2 – `parte2_juego/lib`
* `model.dart` – modelo `GameState`, serializadores/parsers **TXT** (`clave=valor`, encabezado `APAGON-SAVE v1` y cierre `END`), **XML** (paquete `xml`) y **JSON**, validación con `SaveFormatError` de mensajes legibles, y `Store` (archivos en `Documents/partidas`, escritura atómica `.tmp` → rename).
* `pages.dart` – menú, partida, partidas guardadas (metadatos, etiquetas, ver contenido, exportar, compartir, importar, eliminar), opciones.

Datos guardados: estado del tablero, puntuación, tiempo, configuraciones (sonido, vibración, contador, tema) e historial de movimientos. Se autoguarda cuando la app pasa a segundo plano, de modo que **Continuar** recupera la partida tras cerrar y abrir la app. Un archivo vacío, incompleto o corrupto aparece marcado como "Dañada" sin afectar a las demás partidas.

Reglas del juego: tocar una luz invierte ella y sus 4 vecinas; se gana apagándolas todas. Los tableros se generan aplicando toques aleatorios a un tablero apagado, por lo que siempre tienen solución. Puntos = `tamaño·400 − 10·movimientos − segundos`. Ganar el Nivel 1 desbloquea el Nivel 2.

## 5. Pruebas

Pruebas automáticas (`cd parte2_juego && flutter test`): ida y vuelta TXT/XML/JSON, archivos vacíos y truncados → 10/10 aprobadas.

### Matriz de pruebas

> Probado hasta ahora en un único dispositivo Android real (Android 14). Las demás filas e iOS siguen pendientes. Las columnas *Resultado obtenido* y *Evidencia* deben completarse con la ejecución real en cada sistema (no se rellenan sin haberlas hecho).

| # | SO / versión | Dispositivo / simulador | Pasos | Resultado esperado | Resultado obtenido | Evidencia |
|---|---|---|---|---|---|---|
| 1 | Android | _pendiente_ | Instalar P1, modo avión, abrir app | Funciona sin Internet | _pendiente_ | captura |
| 2 | Android 14 · Samsung SM-G998U (físico, USB) | P1: abrir `datos.json`, `config.xml`, `notas.md` | Resaltado y formato correctos | Resaltado y formato correctos en JSON y XML (iOS pendiente) | `capturas/p1_android_json.png`, `p1_android_xml.png` |
| 3 | Android 14 · Samsung SM-G998U (físico, USB) | P1: abrir `imagen_demo.png`, zoom y rotar | Zoom y rotación fluidos | Imagen mostrada con miniatura y visor; botones de zoom/rotación presentes (zoom táctil no verificado; iOS pendiente) | `capturas/p1_android_imagen.png` |
| 4 | Android/iOS | _pendiente_ | P1: elegir carpeta y cancelar el selector | Mensaje, sin cierre | _pendiente_ | captura |
| 5 | Android/iOS | _pendiente_ | P1: renombrar, copiar, mover, eliminar (confirmar) | Operaciones correctas | _pendiente_ | captura |
| 6 | Android/iOS | _pendiente_ | P1: abrir archivo no soportado | Diálogo abrir/compartir/exportar | _pendiente_ | captura |
| 7 | Android/iOS | _pendiente_ | P1: favoritos y recientes, reiniciar app | Persisten | _pendiente_ | captura |
| 8 | Android 14 · Samsung SM-G998U (físico, USB) | P2: jugar nivel 1, guardar en .txt/.xml/.json | 3 archivos con metadatos | Guardado en .xml correcto (contenido verificado); .txt y .json cubiertos por pruebas unitarias; iOS pendiente | `capturas/p2_android_guardar_dialogo.png` |
| 9 | Android 14 · Samsung SM-G998U (físico, USB) | P2: cerrar la app a mitad de partida y reabrir | "Continuar" restaura estado | Tras `force-stop` y reabrir, aparece "Continuar" con 2 mov. y el progreso (iOS pendiente) | `capturas/p2_android_continuar.png` |
| 10 | Android 14 · Samsung SM-G998U (físico, USB) | P2: dañar un archivo guardado (vaciar/truncar) | Error legible, otras partidas intactas | Archivos vacío y TXT incompleto marcados como "Dañada" con mensaje legible; la partida válida sigue intacta (iOS pendiente) | `capturas/p2_android_lista_partidas.png` |
| 11 | Android/iOS | _pendiente_ | P2: exportar/compartir partida | Se envía al destino elegido | _pendiente_ | captura |
| 12 | Android/iOS | _pendiente_ | Cambiar tema Guinda/Azul y modo claro/oscuro del sistema | Colores adaptados | _pendiente_ | captura |
| 13 | Android/iOS | _pendiente_ | Rotar el dispositivo | UI responsiva | _pendiente_ | captura |

## 6. Estado actual y limitaciones

* Compilación Android verificada desde Windows. **iOS no puede compilarse en Windows**: los proyectos iOS están generados y configurados (`ios/`), pero hay que compilar y probar en macOS con Xcode (§3). El despliegue mínimo de iOS 15 debe confirmarse en Xcode (`IPHONEOS_DEPLOYMENT_TARGET = 15.0` ya configurado en el proyecto; el Podfile se genera en macOS con `flutter pub get`).
* La fecha de creación no se expone en `dart:io` en Android/iOS: se muestra "No disponible".
* Copiar/mover carpetas completas no está implementado (sólo archivos).
* En Android 11+ el selector de carpetas devuelve rutas de árbol SAF limitadas; si el sistema no permite listarlas la app muestra un aviso y no se bloquea.

## 7. Conclusiones

Flutter permitió un único código para ambos sistemas, delegando en plugins las APIs nativas de acceso seguro (SAF y Document Picker). Lo más importante fue respetar el modelo de seguridad de cada SO: usar el espacio privado por defecto y acceder a ubicaciones externas sólo con selectores del sistema, validando y manejando cada fallo.

## 8. Bibliografía (APA)

* Android Developers. (s. f.). *Access documents and other files from shared storage*. https://developer.android.com/training/data-storage/shared/documents-files
* Apple Inc. (s. f.). *UIDocumentPickerViewController*. https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller
* Flutter. (s. f.). *Flutter documentation*. https://docs.flutter.dev
* JetBrains. (s. f.). *Kotlin Multiplatform*. https://kotlinlang.org/docs/multiplatform.html
