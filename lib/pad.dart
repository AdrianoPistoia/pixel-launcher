import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'apps.dart';
import 'ui.dart';

/// Lo que hace cada botón del mando: confirmar, volver, menú (como mantener apretado) y vista.
enum PadButton { ok, back, menu, view }

// Android nombra los botones por posición: A abajo, B derecha, X izquierda, Y arriba.
const _south = LogicalKeyboardKey.gameButtonA;
const _east = LogicalKeyboardKey.gameButtonB;
const _west = LogicalKeyboardKey.gameButtonX;
const _north = LogicalKeyboardKey.gameButtonY;

/// Layouts de mando: qué botón físico hace cada cosa y cómo se llama en pantalla.
/// Nintendo confirma con el de la derecha; PlayStation es como Xbox con otros símbolos.
typedef PadLayout = ({String name, String shoulders, Map<PadButton, (LogicalKeyboardKey, String)> keys});

final padLayouts = <String, PadLayout>{
  'xbox': (
    name: 'Xbox',
    shoulders: 'LB RB',
    keys: {
      PadButton.ok: (_south, 'A'),
      PadButton.back: (_east, 'B'),
      PadButton.menu: (_west, 'X'),
      PadButton.view: (_north, 'Y'),
    },
  ),
  'nintendo': (
    name: 'Nintendo',
    shoulders: 'L R',
    keys: {
      PadButton.ok: (_east, 'A'),
      PadButton.back: (_south, 'B'),
      PadButton.menu: (_north, 'X'),
      PadButton.view: (_west, 'Y'),
    },
  ),
  'playstation': (
    name: 'PlayStation',
    shoulders: 'L1 R1',
    keys: {
      PadButton.ok: (_south, '✕'),
      PadButton.back: (_east, '○'),
      PadButton.menu: (_west, '□'),
      PadButton.view: (_north, '△'),
    },
  ),
};

PadLayout get _layout => padLayouts[store.pad] ?? padLayouts['xbox']!;

LogicalKeyboardKey padKey(PadButton b) => _layout.keys[b]!.$1;

String padLabel(PadButton b) => _layout.keys[b]!.$2;

String get shoulderLabel => _layout.shoulders;

/// ¿Es confirmar? El botón del layout, o Enter/centro del D-pad (teclado y control remoto).
bool isOk(LogicalKeyboardKey k) =>
    k == padKey(PadButton.ok) || k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.select;

/// Atajos de toda la app según el layout. Volver solo se frena acá: lo maneja la shell, que lo
/// escucha aunque no haya nada con foco.
Map<ShortcutActivator, Intent> padShortcuts() => {
  SingleActivator(padKey(PadButton.ok)): const ActivateIntent(),
  SingleActivator(padKey(PadButton.menu)): const MenuIntent(),
  SingleActivator(padKey(PadButton.back)): const DoNothingAndStopPropagationIntent(),
};
