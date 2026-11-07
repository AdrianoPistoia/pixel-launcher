# Pixel Launcher

Launcher pixel-art para Android, inspirado en las features de [TrinketOS](https://github.com/ismslv/trinketos), pero con código propio.
TrinketOS es closed-source: acá no hay código ni assets suyos. El mapa de features y la comparación con otros launchers están en [docs/features.md](docs/features.md).

## Requisitos

- Flutter 3.35+ y el Android SDK (`flutter doctor`). La primera vez corré `flutter doctor --android-licenses`.
- Un celular con depuración USB activada, o el emulador `pixel7`.

## Herramientas

```powershell
.\dev.ps1 run       # corre en el celu/emulador con hot reload
.\dev.ps1 install   # build release + instala por adb
.\dev.ps1 home      # lo fija como launcher por defecto (adb)
.\dev.ps1 test      # analyze + tests
.\dev.ps1           # lista todos los comandos
```

En el celular también podés elegirlo desde la pestaña **SYS → Elegir launcher por defecto**.

## Estructura

| Archivo | Qué hay |
|---|---|
| `lib/ui.dart` | Sistema de diseño: paleta, fuente, tamaños (`Px`), `PixelTile` y `PixelIcon`. **Re-skin acá.** |
| `lib/main.dart` | Shell: barra de trinkets, pestañas y páginas. **Agregar pestañas acá** (lista `tabs`). |
| `lib/apps.dart` | Estado compartido: apps instaladas y fijadas (`store`). |
| `lib/pages.dart` | Tipos de página (`PinnedPage`, `AppsPage`, `SystemPage`) y el menú de app. |
| `lib/tabs.dart` | Tipos de pestaña (`tabKinds`), pestañas del usuario (`tabStore`), la de utilidades y la pestaña "+". |
| `lib/views.dart` | Las vistas Terminal, Bitácora, Consola y Órbita. |
| `lib/utilities.dart` | Catálogo de utilidades (`utilities`): reloj, cronómetro, cuenta arriba, web, apps. |
| `lib/trinkets.dart` | Widgets propios (`ClockTrinket`, `MoonTrinket`) y la `TrinketBar`. |
| `assets/fonts/` | VT323 (licencia OFL). |

## Extenderlo

- **Nuevo tipo de pestaña:** un widget (en `views.dart` o `pages.dart`) y una entrada en `tabKinds` (`lib/tabs.dart`). Aparece solo en el menú de "+".
- **Pestañas:** todas se crean desde "+" y se renombran, mueven o borran manteniéndolas apretadas. SYS y "+" son fijas.
- **Uso:** cada apertura de app pasa por `store.launch`, que cuenta aperturas por hora. SYS → "Copiar datos de uso" lo exporta como JSON.
- **Nuevo trinket:** un widget en `trinkets.dart` y sumarlo a `TrinketBar`.
- **Nueva utilidad para pestañas:** una entrada en `utilities` (`lib/utilities.dart`) con `label`, `create` (config inicial) y `build`. Su estado va en la config y se guarda con `save`.
- **Otro look:** los colores, `Px.unit` (grosor del pixel) y `Px.iconRes` (cuánto se pixelan los íconos).
- **Que funcione con gamepad:** cualquier cosa clickeable tiene que usar `PixelTile`. Así recibe foco del D-pad y el botón A la activa.
