# Mapa de features

Inspiración: [TrinketOS](https://github.com/ismslv/trinketos) (capítulos I–III) más otros launchers open source.
TrinketOS es **closed-source y sin licencia**: tomamos ideas de features, **no** código, sprites, íconos, sonidos ni nombres propios (Merlin, glyphs, etc.).

Estado: ✅ en el esqueleto · 🔜 siguiente (fácil, Flutter puro o un paquete) · 🧭 más adelante (requiere código nativo o mucho trabajo) · 💤 descartado por ahora

## Estructura

| Feature (TrinketOS) | También en | Estado | Cómo |
|---|---|---|---|
| Pestañas modulares con páginas | — (único de TrinketOS) | ✅ | lista `tabs` en `lib/main.dart` |
| Swipe entre pestañas | Kvaesitso, Olauncher | ✅ | `PageView` |
| Pestaña de ajustes fija | todos | ✅ | `SystemPage` |
| Pestaña "+": crear cualquier tipo de pestaña; renombrar, mover y borrar (también manteniendo apretada la pestaña) | — | ✅ | `AddTabPage`, `showTabMenu`; SYS y "+" no se borran |
| Vistas Terminal, Bitácora, Consola y Órbita (de las propuestas de UX). La Terminal de búsqueda ahora es la vista "buscar" de la pestaña TERMINAL | — | ✅ | `lib/views.dart` |
| Pestaña TERMINAL: Claude Code (login Pro/Max) en Termux → Debian, con chat pixel por sesión (D-pad, ESCRIBIR/DETENER), pasos de instalación, permisos con diálogo según riesgo y servidor MCP del launcher (Shizuku, apps, pestañas); vistas claude.ai (web + app oficial) y buscar; Y o menú cambia de vista | — | ✅ | `lib/terminal.dart`, `lib/claude.dart`, `termux/`. Probada en el emulador x86_64 (puente, MCP, permisos, Shizuku); falta el handheld arm64, con login real y compilando el launcher. Ver `docs/terminal.md` |
| Adjuntar archivos al mensaje de Claude (fotos, capturas, PDFs, lo que sea) con selector del sistema; el mensaje es una caja grande de varias líneas; el aviso de Y se muestra una sola vez para todas las vistas de TERMINAL | — | ✅ | `lib/terminal.dart` (`_compose`), `lib/claude.dart` (`Attachment`), `MainActivity.kt` (`pickFiles`), `termux/bridge.js`. Falta probarlo en el teléfono |
| Vista Anillo: canales elegidos por pestaña (menú → Elegir canales; sin elegir, hasta 8: fijadas y después las más usadas) en una órbita inclinada; gira con flechas, swipe o tocando, el de adelante abre; panel ancho con nombre, canal y detalle | ALTIMIT Mine OS (.hack//G.U.) | ✅ | `RingPage` en `lib/gu.dart` |
| Vistas animadas: Órbita viva (anillos que giran, estrellas, apertura con caída a la luna), Consola arcade (flote, brillo, rebote, persianas al abrir) y Terminal que bootea (booteo tipeado, cascada, coincidencias resaltadas, barra al abrir) | — | ✅ | `docs/animaciones.md` |
| Registro de uso: aperturas por app y por hora, exportable | — | ✅ | `store.launch`, SYS → "Copiar datos de uso" |
| Barra de pestañas arriba o abajo, en un renglón deslizable | — | ✅ | SYS → "Pestañas" |
| Pestañas de utilidades en grilla 2×2: mover entre las 4 posiciones, tamaño (1 casillero, fila, columna o todo), pantalla completa momentánea (MAX/MIN) y quitar | — | ✅ | `CustomTabPage`; lógica pura en `cellsOf`/`moveTo`/`fits` (con tests) |
| Utilidades: reloj, cronómetro, cuenta arriba, web, accesos a apps | Kvaesitso (widgets) | ✅ | `lib/utilities.dart` |
| Utilidad Fotos: cuadro que pasa fotos cada 15 s, pixeladas o no; agregar, quitar (la original queda), borrar del teléfono, siguiente | — | ✅ | `PhotosUtil`; selector del sistema por `MainActivity.kt` (copia las fotos a la app, sin permisos) |
| Web: recargar y cambiar dirección desde su menú | — | ✅ | `_webs` (controller por config) |
| Utilidades: notas, lista de tareas, cuenta regresiva, clima | — | 🔜 | una entrada más en `utilities` |
| Pestaña de 2 páginas / modo una página | — | 🔜 | `Row` de 2 páginas en landscape |
| Página: lista de apps | todos | ✅ | `AppsPage` |
| Página: apps fijadas (INICIO). En las dos orientaciones llena filas y suma filas hacia abajo; en vertical, 2 columnas | — | ✅ | `PinnedPage`, se fija con long-press |
| Página: íconos grandes (carrusel horizontal) | — | 🔜 | `PageView` horizontal |
| Página: notas de texto / markdown | — | 🔜 | `Text` de un archivo, después `flutter_markdown` |
| Página: lista de tareas | — | 🔜 | lista + `shared_preferences` |
| Página: imágenes | — | ✅ | utilidad Fotos (en pantalla completa con MAX) |
| Consola: vista carrusel o panorámica (grilla de tarjetas, 2 filas a la vista) | Steam, Playnite | ✅ | Y o menú de la pestaña; se guarda en la pestaña (`view`) |
| Página: explorador de archivos | — | 🧭 | `dart:io` + permiso de almacenamiento |
| Página: web / navegador (cap. III) | — | ✅ | utilidad Web (`webview_flutter`). Al tocarla toma el foco y se lleva todos los gestos hasta "atrás" (`webFocus`) |
| Abrir la web en un navegador elegido | — | ✅ | SYS → Navegador; menú de la Web → "Abrir en navegador" |
| Tapps: mini-apps HTML/JS como pestaña | Kvaesitso (SDK de plugins) | 🧭 | `webview_flutter` + carpeta local |
| Lector de libros, reproductor de cassettes (cap. III) | — | 🧭 | páginas propias |
| Links a RetroArch | ES-DE, Pegasus | 🧭 | `android_intent_plus` con extras |

## Apps

| Feature | También en | Estado | Cómo |
|---|---|---|---|
| Abrir apps, orden alfabético | todos | ✅ | `installed_apps` |
| Búsqueda | KISS, Kvaesitso (lo ponen primero) | ✅ | filtro en `AppsPage` |
| Menú de app (long-press): fijar en INICIO, info | todos | ✅ | `showAppMenu`, persistido en `shared_preferences` |
| Íconos pixelados | — | ✅ | `PixelIcon` (`Px.iconRes`) |
| Ocultar apps | todos | 🔜 | set de packages en prefs |
| Renombrar apps | Olauncher, TrinketOS | 🔜 | mapa package→nombre en prefs |
| Colorear íconos | — | 🔜 | `ColorFiltered` |
| Detectar instalaciones al instante | FLauncher | 🧭 | hoy recarga al volver al launcher; canal nativo `PACKAGE_ADDED` |
| Icon packs | Kvaesitso, Lawnchair, KISS | 🧭 | leer `appfilter.xml` del pack (nativo) |
| Badges de notificaciones | Kvaesitso, Lawnchair | 🧭 | `NotificationListenerService` nativo |
| Carpetas | Lawnchair, Discreet | 💤 | las pestañas cumplen ese rol |

## Trinkets (widgets propios)

| Feature | También en | Estado | Cómo |
|---|---|---|---|
| Reloj y fecha | todos | ✅ | `ClockTrinket` |
| Fase lunar, como ícono pixel-art de cada fase (vista desde el hemisferio sur) | — | ✅ | `moonPhase()` + `moonGlyph()` (con test), dibujado con `PixelGlyph` |
| Signo del zodíaco, dados, texto/imagen custom | — | 🔜 | Dart puro |
| Batería, Wi-Fi, Bluetooth | — | 🔜 | `battery_plus`, `connectivity_plus` |
| Brillo y volumen con barra | — | 🧭 | canal nativo |
| Reproductor de música | Kvaesitso | 🧭 | MediaSession vía listener nativo |
| Calendario, clima | Kvaesitso | 🧭 | `device_calendar` / API de clima |
| Widgets de Android | Kvaesitso, Lawnchair | ✅ | utilidad Widget: selector del sistema + `AppWidgetHost` en `MainActivity.kt`, mostrado con `AndroidView`. Sin D-pad adentro del widget |

## Controles

| Feature | También en | Estado | Cómo |
|---|---|---|---|
| Navegar con D-pad o gamepad, A para activar | FLauncher, Pegasus | ✅ | `FocusableActionDetector` en `PixelTile` |
| Todo con mando: confirmar, volver (cierra diálogos, suelta la web), menú (= mantener apretado), vista; la web se entra y se scrollea; cada pestaña toma el foco al entrar | consolas | ✅ | `lib/pad.dart`, `_PageScope` en la shell |
| Layout del mando Xbox (por defecto), Nintendo (confirma el de la derecha) o PlayStation (✕ ○ □ △); las ayudas en pantalla usan sus nombres | ES-DE, RetroArch | ✅ | SYS → Mando; `padLayouts` |
| Cursor de selección propio | — | ✅ | `>` y colores invertidos |
| L1/R1 cambian de pestaña | consolas | ✅ | `HardwareKeyboard` en la shell |
| Botón de apagado (ícono ⏻ pixel-art) al lado de la hora: apagar, reiniciar, cancelar | — | ✅ | con root, `svc power`; sin root, menú de apagado de Android vía servicio de accesibilidad (`PowerService.kt`) |
| Remapear botones a acciones | μLauncher (gestos→acciones) | 🔜 | `Shortcuts` armado desde config |
| Gestos (swipe, doble tap) | Olauncher, μLauncher | 🔜 | `GestureDetector` en `Shell` |
| Teclado en pantalla propio | — | 💤 | el del sistema alcanza en un celular |

## Diseño

| Feature | Estado | Cómo |
|---|---|---|
| Fuente pixel, bordes rectos, sombra dura | ✅ | `Px` en `lib/ui.dart` |
| Estilos: pixel o G.U. (navy, líneas cian, acentos ámbar, paneles biselados, fondo de panal, fuente Space Grotesk, íconos lisos) | ✅ | `Px.style` (SYS → Estilo); los valores de `Px` son getters por estilo. Panal y espada en `lib/gu.dart` |
| SYS en G.U.: menú corrido a la derecha con una espada de sierra y cadena cruzando de fondo | ✅ | `SwordBackdrop` (dibujo propio, `CustomPainter`) |
| Más paletas con nombre | 🔜 | otro valor de `PxStyle` |
| Fondos propios, incluso GIF animados | 🔜 | `Image` (Flutter anima GIF solo) |
| Pixelar fondos | 🔜 | el mismo truco de `cacheWidth` que los íconos |
| Efectos de pantalla (CRT, scanlines, ruido) | 🔜 | `CustomPainter` encima de todo |
| Márgenes, escala de UI, asimetría | 🔜 | constantes de `Px` → prefs |
| Cursores y glifos propios | 🧭 | editor de grillas |

## Personalidad

| Feature | Estado | Cómo |
|---|---|---|
| Sprite animado acompañante | 🔜 | spritesheet propio + `Ticker` |
| Sonidos de UI, música ambiente | 🧭 | `audioplayers` |
| Skills, gorros, logros | 🧭 | contadores en prefs |
| Bloqueo con glifo | 💤 | — |

## Launchers comparados (base posible)

| Launcher | Licencia | Stack | Fuerte en | Reskin pixel |
|---|---|---|---|---|
| TrinketOS | cerrado | ? | personalidad, pestañas, gamepad | — |
| Kvaesitso | GPL-3.0 | Kotlin/Compose | búsqueda, widgets, plugins | medio (Material 3 en todos lados) |
| Olauncher | GPL-3.0 | Kotlin/Views | minimalismo, solo texto | fácil |
| KISS | GPL-3.0 | Java/Views | búsqueda, historial | medio |
| μLauncher | MIT | Kotlin/Views | gestos → acciones | fácil–medio |
| PieLauncher | MIT | Java/Canvas | todo dibujado a mano | fácil |
| Lawnchair / Neo | Apache-2.0 / GPL-3.0 | Launcher3 | todo lo de Pixel | muy difícil |
| FLauncher / LtvLauncher | GPL-3.0 | **Flutter** | navegación con D-pad (TV) | fácil |
| Pegasus | GPL-3.0 | Qt/QML | frontend de juegos | solo QML |

**Por qué Flutter desde un esqueleto:** controlamos cada pixel (fuente, bordes, `FilterQuality.none`), hay hot reload en el celu y la licencia la elegís vos. FLauncher es la referencia para el canal nativo y la navegación con D-pad. Si alguna vez querés un fork en Kotlin, conviene Olauncher (look de terminal) o Kvaesitso (widgets y plugins).
