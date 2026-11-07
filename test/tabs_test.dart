import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_launcher/tabs.dart';
import 'package:pixel_launcher/utilities.dart';

Config w(int slot, [String size = '1x1']) => {'type': 'apps', 'apps': <String>[], 'slot': slot, 'size': size};

void main() {
  test('formato de tiempo', () {
    expect(fmt(const Duration(seconds: 61)), '00:01:01');
    expect(
      fmt(const Duration(days: 3, hours: 4, minutes: 5, seconds: 6, milliseconds: 789), tenths: true),
      '3d 04:05:06.7',
    );
  });

  test('casilleros por tamaño (0 1 / 2 3)', () {
    expect(cellsOf(3, '1x1'), {3});
    expect(cellsOf(3, '2x1'), {2, 3});
    expect(cellsOf(1, '1x2'), {1, 3});
    expect(cellsOf(2, '2x2'), {0, 1, 2, 3});
  });

  test('mover: intercambia con la de 1 casillero que estorba', () {
    final ws = [w(0), w(1)];
    expect(moveTo(ws, 0, 1), isTrue);
    expect([ws[0]['slot'], ws[1]['slot']], [1, 0]);
  });

  test('mover una fila entera: las de abajo suben', () {
    final ws = [w(0, '2x1'), w(2), w(3)];
    expect(moveTo(ws, 0, 2), isTrue);
    expect([for (final x in ws) x['slot']], [2, 0, 1]);
  });

  test('mover no pisa utilidades grandes', () {
    final ws = [w(0), w(2, '2x1')];
    expect(moveTo(ws, 0, 3), isFalse);
    expect(ws[0]['slot'], 0); // sin cambios
  });

  test('tamaños que entran', () {
    final ws = [w(0), w(1)];
    expect(fits(ws, 0, 0, '1x2'), isTrue); // baja a la columna izquierda: libre
    expect(fits(ws, 0, 0, '2x1'), isFalse); // la fila de arriba la comparte con la otra
  });

  test('migración: utilidades sin lugar quedan como el acomodo viejo', () {
    final one = [
      <String, dynamic>{'type': 'clock'},
    ];
    normalizeWidgets(one);
    expect([one[0]['slot'], one[0]['size']], [0, '2x2']);
    final three = [
      for (var i = 0; i < 3; i++) <String, dynamic>{'type': 'clock'},
    ];
    normalizeWidgets(three);
    expect([for (final x in three) '${x['slot']}:${x['size']}'], ['0:1x1', '1:1x1', '2:2x1']);
  });

  testWidgets('cada casillero libre muestra + AGREGAR', (tester) async {
    Future<void> pumpWith(int n) async {
      tabStore.tabs = [
        {
          'kind': 'custom',
          'name': 'X',
          'widgets': [for (var i = 0; i < n; i++) w(i)],
        },
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CustomTabPage(0, key: ValueKey(n))),
        ),
      );
    }

    await pumpWith(3);
    expect(find.textContaining('AGREGAR'), findsOneWidget);
    expect(find.textContaining('MAX'), findsNWidgets(3));
    await pumpWith(4);
    expect(find.textContaining('AGREGAR'), findsNothing);
    await pumpWith(1);
    expect(find.textContaining('AGREGAR'), findsNWidgets(3));
  });
}
