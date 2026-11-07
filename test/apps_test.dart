import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:pixel_launcher/apps.dart';
import 'package:pixel_launcher/tabs.dart';
import 'package:pixel_launcher/views.dart';

void main() {
  List<int> at(Map<int, int> hours) => [for (var h = 0; h < 24; h++) hours[h] ?? 0];

  setUp(() {
    store
      ..apps = [
        for (final n in ['Mapas', 'Música', 'Notas', 'Fotos']) AppInfo.create({'name': n, 'package_name': n}),
      ]
      ..usage = {
        'Música': at({8: 5}), // mañana
        'Notas': at({21: 2, 22: 1}), // noche
        'Mapas': at({9: 1}),
      };
  });

  test('sugerencias según la hora (la hora pesa doble que las vecinas)', () {
    expect(store.suggestions(8).map((a) => a.name), ['Música', 'Mapas']);
    expect(store.suggestions(22).map((a) => a.name), ['Notas']);
    expect(store.suggestions(3), isEmpty);
  });

  test('por uso: más abiertas primero, a igual uso alfabético', () {
    expect(store.byUse.map((a) => a.name), ['Música', 'Notas', 'Mapas', 'Fotos']);
  });

  test('pestañas iniciales: todas las vistas más las de utilidades viejas', () {
    final old = jsonEncode([
      {'name': 'UTIL', 'widgets': []},
    ]);
    final tabs = TabStore.initialTabs(old);
    expect(tabs.map((t) => t['kind']), ['inicio', 'apps', 'terminal', 'bitacora', 'consola', 'orbita', 'custom']);
    expect(tabs.last['name'], 'UTIL');
    expect(TabStore.initialTabs(null), hasLength(6));
  });

  test('inicial para agrupar: sin tildes y # si no es letra', () {
    expect(initialOf('Ópera'), 'O');
    expect(initialOf('ñandú'), 'N');
    expect(initialOf('9gag'), '#');
  });
}
