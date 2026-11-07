# Vistas animadas: checklist

Propuesta: https://claude.ai/artifact/JpGNhUasf3vffEocLgy1s6

Reglas para todo: movimiento a saltos de `Px.unit` y curvas en pasos; con
`MediaQuery.disableAnimationsOf(context)` queda la vista de hoy y abrir es instantáneo;
ninguna animación de apertura pasa de 500 ms antes de `store.launch`; sin paquetes nuevos.
Cada paso termina con `flutter analyze && flutter test` en verde.

## Órbita viva (`OrbitaPage`)

- [x] O1 Un `Ticker` en `_OrbitaPageState` (acumula giro solo cuando no está frenado; `SingleTickerProviderStateMixin`, `dispose`).
- [x] O2 Los anillos giran: ángulo `starts[ring] + t·velocidad[ring]` (1 vuelta cada ~20 s, ~35 s, ~60 s); posiciones redondeadas a `Px.unit`. El `hit()` del arrastre usa las mismas posiciones.
- [x] O3 Se frena mientras `drag != null` o un planeta tiene foco del D-pad.
- [x] O4 Estrellas que titilan a saltos y latido de la luna en `_SkyPainter` (recibe `t`, `shouldRepaint` lo compara).
- [x] O5 Abrir (tap, D-pad o soltar el arrastre): estela → el planeta cae en la luna → destello, después `store.launch`.
- [x] O6 Sin animaciones del sistema: órbita quieta y abrir directo.
- [x] O7 Probado en el emulador con captura; estado actualizado en `docs/features.md`.

## Consola arcade (`ConsolaPage`)

- [x] K1 `go()` con `Curves.easeOutBack` y 260 ms.
- [x] K2 Controller en `_ConsolaPageState`; la tarjeta elegida flota en 2 cuadros (sube 4 px y baja).
- [x] K3 Brillo diagonal en pasos que cruza la tarjeta elegida cada ~2,4 s (`CustomPaint` con `Px.fg` al 22 %).
- [x] K4 «PULSÁ A» titilando arriba de la leyenda.
- [x] K5 Persianas de pixel (10 franjas, 4 pasos) con el nombre de la app antes de `store.launch`, por tap y por tecla A.
- [x] K6 Sin animaciones del sistema: sin flote, brillo ni persianas; `go()` salta.
- [x] K7 Probado en el emulador con captura; estado actualizado en `docs/features.md`.

## Terminal que bootea (`TerminalPage`)

- [x] T1 Booteo de ~900 ms al entrar: 4 líneas tipeadas con datos reales (apps instaladas, aperturas registradas, hora) y " OK" al final de cada una.
- [x] T2 Cualquier tecla o toque saltea el booteo.
- [x] T3 Las sugerencias de la hora aparecen en cascada (60 ms entre una y otra).
- [x] T4 `PixelTile` acepta un parámetro opcional para resaltar parte del label (`Text.rich`, `Px.accent`); los resultados resaltan lo que coincide.
- [x] T5 Cursor de bloque en la línea de comandos (`cursorWidth: 10`).
- [x] T6 Enter llena `[##########]` en 10 pasos (~400 ms) y después `store.launch`.
- [x] T7 Sin animaciones del sistema: sin booteo ni barra.
- [x] T8 Probado en el emulador con captura; estado actualizado en `docs/features.md`.

## Cierre

- [x] F1 `flutter analyze && flutter test` en verde con todo junto.
- [x] F2 `flutter build apk --release`.
- [x] F3 APK subido a Dropbox.
