import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_launcher/apps.dart';
import 'package:pixel_launcher/pad.dart';

void main() {
  test('cada layout usa los 4 botones, uno por función', () {
    for (final l in padLayouts.values) {
      expect({for (final (k, _) in l.keys.values) k}.length, 4, reason: l.name);
      expect(l.keys.keys.toSet(), PadButton.values.toSet(), reason: l.name);
    }
  });

  test('Nintendo confirma con el de la derecha y vuelve con el de abajo', () {
    store.pad = 'nintendo';
    expect(isOk(LogicalKeyboardKey.gameButtonB), isTrue);
    expect(isOk(LogicalKeyboardKey.gameButtonA), isFalse);
    expect(padKey(PadButton.back), LogicalKeyboardKey.gameButtonA);
    store.pad = 'xbox';
    expect(isOk(LogicalKeyboardKey.gameButtonA), isTrue);
    expect(padLabel(PadButton.menu), 'X');
  });
}
