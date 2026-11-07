import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Canal con el código nativo (`MainActivity.kt`): fotos, borrar fotos y apagar.
const native = MethodChannel('pixel_launcher');

/// Estado compartido: apps instaladas, fijadas en INICIO, navegador elegido, layout del mando y
/// registro de uso. Las páginas lo escuchan.
class AppStore extends ChangeNotifier {
  List<AppInfo> apps = [];
  List<String> pinned = []; // packageNames, en el orden en que se fijaron
  String? browser; // packageName del navegador para abrir webs; null = el del sistema
  String pad = 'xbox'; // layout del mando: clave de padLayouts (pad.dart)
  Map<String, List<int>> usage = {}; // packageName → aperturas por hora del día (24 casilleros)
  late final _prefs = SharedPreferencesAsync();

  Future<void> load() async {
    final list = await InstalledApps.getInstalledApps(
      excludeSystemApps: false,
      withIcon: true,
      detectPlatformType: false,
    );
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    apps = list;
    pinned = await _prefs.getStringList('pinned') ?? [];
    browser = await _prefs.getString('browser');
    pad = await _prefs.getString('pad') ?? 'xbox';
    final raw = await _prefs.getString('usage');
    usage = raw == null
        ? {}
        : {for (final e in (jsonDecode(raw) as Map).entries) e.key as String: List<int>.from(e.value as List)};
    notifyListeners();
  }

  /// Abre la app y suma una apertura en la hora actual.
  Future<void> launch(String pkg) async {
    InstalledApps.startApp(pkg);
    (usage[pkg] ??= List.filled(24, 0))[DateTime.now().hour]++;
    await _prefs.setString('usage', jsonEncode(usage));
  }

  int uses(String pkg) => usage[pkg]?.fold<int>(0, (a, b) => a + b) ?? 0;

  /// Todas las apps, las más abiertas primero (a igual uso, alfabético).
  List<AppInfo> get byUse => [...apps]
    ..sort((a, b) {
      final d = uses(b.packageName) - uses(a.packageName);
      return d != 0 ? d : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

  /// Las más abiertas cerca de esta hora (la hora pesa doble que las vecinas). Solo apps con uso.
  List<AppInfo> suggestions(int hour, {int count = 3}) {
    int score(AppInfo a) {
      final u = usage[a.packageName];
      return u == null ? 0 : u[hour] * 2 + u[(hour + 23) % 24] + u[(hour + 1) % 24];
    }

    return (apps.where((a) => score(a) > 0).toList()..sort((a, b) => score(b) - score(a))).take(count).toList();
  }

  /// Fijadas que siguen instaladas, en orden.
  List<AppInfo> get pinnedApps => [for (final p in pinned) ...apps.where((a) => a.packageName == p)];

  bool isPinned(String pkg) => pinned.contains(pkg);

  Future<void> togglePin(String pkg) async {
    if (!pinned.remove(pkg)) pinned.add(pkg);
    notifyListeners();
    await _prefs.setStringList('pinned', pinned);
  }

  Future<void> setBrowser(String? pkg) async {
    browser = pkg;
    notifyListeners();
    await (pkg == null ? _prefs.remove('browser') : _prefs.setString('browser', pkg));
  }

  Future<void> setPad(String layout) async {
    pad = layout;
    notifyListeners();
    await _prefs.setString('pad', layout);
  }
}

final store = AppStore();
