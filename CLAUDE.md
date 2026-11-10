# Pixel Launcher

Launcher Android en Flutter con estética pixel-art. El usuario escribe en español rioplatense; respondé igual.

- TrinketOS (ismslv/trinketos) es closed-source: usalo solo como referencia de features. No copies sus assets, sprites, textos ni nombres.
- Roadmap y estado: `docs/features.md`. Cuando implementes una feature, actualizá su estado ahí.
- Todo lo visual sale de `Px` (`lib/ui.dart`). No hardcodees colores ni fuentes en otros archivos.
- `Px` tiene dos estilos (pixel y G.U., `Px.style`): sus colores y fuentes son getters, no `const`, así que no van en expresiones `const`. Tamaños de letra pensados para VT323: `Px.sz(n)`.
- Abrir apps siempre con `store.launch(pkg)` (registra el uso que alimenta Terminal, Consola y Órbita), nunca `InstalledApps.startApp` directo.
- Tipos de pestaña en `tabKinds` (`lib/tabs.dart`); todas las pestañas del usuario son borrables, solo SYS y "+" son fijas.
- Diálogos: `showPixelMenu` / `askText` / `showPixelDialog` de `ui.dart`, nunca diálogos Material crudos.
- Utilidades de pestañas: entradas del mapa `utilities`; el estado vive en su config (JSON), no en un State, porque `PageView` destruye las páginas que no se ven. Cada una guarda `slot` (0–3, grilla 2×2) y `size` (`1x1`, `2x1`, `1x2`, `2x2`); cambiá posiciones solo con `moveTo`/`fits` de `tabs.dart`.
- Atajos de gamepad globales (como L1/R1) van en `HardwareKeyboard`, no en `Shortcuts`: al cambiar de pestaña se destruye el widget con foco.
- Botones del mando por función, nunca `gameButtonA` directo: `padKey`/`padLabel`/`isOk` de `lib/pad.dart` (el layout Xbox/Nintendo/PlayStation se elige en SYS). Lo que tenga long-press se abre también con el botón de menú (`MenuIntent`).
- Al probar teclas con `adb shell input keyevent`: si Android está en modo táctil se pierden; mandá antes una flecha del D-pad.
- Todo lo clickeable es un `PixelTile`, así anda con D-pad/gamepad. Nada de ripples Material ni bordes redondeados.
- Para verificar: `flutter analyze && flutter test`. Para probar en el emulador: `.\dev.ps1 emu`, después `.\dev.ps1 run`. Para sacar captura: `adb exec-out screencap -p` desde Bash.
- Paquetes nuevos: solo si Flutter puro no alcanza. Si hace falta código nativo, va en `MainActivity.kt` con un MethodChannel (referencia: FLauncher/LtvLauncher).
