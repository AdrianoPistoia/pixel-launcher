import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:pixel_launcher/apps.dart';
import 'package:pixel_launcher/pages.dart';

Future<void> pumpPinned(WidgetTester tester, Size size) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  store
    ..apps = [
      for (var i = 0; i < 14; i++) AppInfo.create({'name': 'app$i', 'package_name': 'p$i'}),
    ]
    ..pinned = [for (var i = 0; i < 14; i++) 'p$i'];
  await tester.pumpWidget(const MaterialApp(home: Scaffold(body: PinnedPage())));
}

Offset at(WidgetTester tester, String name) => tester.getTopLeft(find.textContaining(RegExp('^.$name\$')));

void main() {
  testWidgets('vertical: misma lógica, 2 columnas que suman filas hacia abajo', (tester) async {
    await pumpPinned(tester, const Size(400, 800));
    expect(at(tester, 'app1').dy, at(tester, 'app0').dy); // misma fila
    expect(at(tester, 'app1').dx, greaterThan(at(tester, 'app0').dx));
    expect(at(tester, 'app2').dy, greaterThan(at(tester, 'app0').dy)); // la tercera baja de fila
    expect(at(tester, 'app2').dx, at(tester, 'app0').dx);
  });

  testWidgets('horizontal: llena filas de izquierda a derecha y suma filas abajo', (tester) async {
    await pumpPinned(tester, const Size(1000, 300));
    expect(at(tester, 'app1').dy, at(tester, 'app0').dy); // misma fila
    expect(at(tester, 'app1').dx, greaterThan(at(tester, 'app0').dx));
    // con 14 apps hacen falta más de 2 filas: la última queda debajo de la segunda fila
    final rows = {for (var i = 0; i < 14; i++) at(tester, 'app$i').dy}.length;
    expect(rows, greaterThan(2));
  });
}
