import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'apps.dart';
import 'claude.dart';
import 'ui.dart';

// Archivos que genera Claude en la sesión (Write): se traen del puente y se abren con otra app.
// Por tipo de archivo se recuerda la última app usada, y esa es la que abre al tocar.

const _kinds = {
  'html': ['html', 'htm', 'svg'],
  'imagen': ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'],
  'pdf': ['pdf'],
  'video': ['mp4', 'mkv', 'webm', 'mov'],
  'audio': ['mp3', 'wav', 'ogg', 'm4a', 'flac'],
  'apk': ['apk'],
  'texto': ['txt', 'md', 'json', 'csv', 'log', 'xml', 'yaml', 'yml', 'dart', 'js', 'py', 'kt', 'sh'],
};

String baseName(String path) => path.split('/').last;

/// Tipo de archivo por su extensión ('html', 'imagen', 'pdf'…); una extensión rara es su propio tipo.
String fileKind(String path) {
  final n = baseName(path);
  final ext = n.contains('.') ? n.split('.').last.toLowerCase() : '';
  for (final MapEntry(key: k, value: exts) in _kinds.entries) {
    if (exts.contains(ext)) return k;
  }
  return ext.isEmpty ? 'archivo' : ext;
}

/// Última app usada por tipo de archivo: {tipo: {pkg, label}}.
class FileOpeners extends ChangeNotifier {
  FileOpeners() {
    SharedPreferences.getInstance().then((p) {
      _prefs = p;
      final raw = p.getString('fileOpeners');
      if (raw != null) {
        _map = (jsonDecode(raw) as Map).map((k, v) => MapEntry('$k', Map<String, String>.from(v as Map)));
        notifyListeners();
      }
    });
  }

  SharedPreferences? _prefs;
  Map<String, Map<String, String>> _map = {};

  Map<String, String>? of(String kind) => _map[kind];

  void set(String kind, Map<String, String>? app) {
    app == null ? _map.remove(kind) : _map[kind] = app;
    _prefs?.setString('fileOpeners', jsonEncode(_map));
    notifyListeners();
  }
}

final fileOpeners = FileOpeners();

/// Abre [path] (de Debian). Sin [choose] usa la app recordada de su tipo; si no hay (o con [choose]),
/// pregunta con cuál y la recuerda.
Future<void> openGenerated(BuildContext context, String path, {bool choose = false}) async {
  final kind = fileKind(path);
  final saved = fileOpeners.of(kind);
  try {
    bridge.say('Trayendo ${baseName(path)}…');
    final local = await bridge.fetchFile(path);
    bridge.say(null);
    if (saved != null && !choose) {
      final err = await native.invokeMethod<String>('openFile', {'path': local, 'pkg': saved['pkg']});
      if (err == null) return;
      bridge.say('No pude abrirlo con ${saved['label']}: $err');
    }
    final apps = List<Map>.from(
      await native.invokeMethod<List>('appsFor', {'path': local}) ?? const [],
    )..sort((a, b) => '${a['label']}'.toLowerCase().compareTo('${b['label']}'.toLowerCase()));
    if (!context.mounted) return;
    if (apps.isEmpty) return bridge.say('No hay ninguna app que abra .$kind.');
    showPixelMenu(context, 'Abrir $kind con…', [
      for (final a in apps)
        (
          '${a['label']}${a['pkg'] == saved?['pkg'] ? '  (última)' : ''}',
          () async {
            fileOpeners.set(kind, {'pkg': '${a['pkg']}', 'label': '${a['label']}'});
            final err = await native.invokeMethod<String>('openFile', {'path': local, 'pkg': a['pkg']});
            if (err != null) bridge.say('No pude abrirlo: $err');
          },
        ),
    ]);
  } catch (e) {
    bridge.say('$e');
  }
}

/// Menú de un archivo generado (long-press o botón de menú del mando).
void showFileMenu(BuildContext context, String path) {
  final kind = fileKind(path);
  final saved = fileOpeners.of(kind);
  showPixelMenu(context, baseName(path), [
    if (saved != null) ('Abrir con ${saved['label']}', () => openGenerated(context, path)),
    ('Abrir con…', () => openGenerated(context, path, choose: true)),
    if (saved != null) ('Olvidar app de $kind', () => fileOpeners.set(kind, null)),
    ('Copiar ruta', () => Clipboard.setData(ClipboardData(text: path))),
  ]);
}

