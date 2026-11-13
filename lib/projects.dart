import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'claude.dart' show uuid4;

/// Proyectos de la lista de sesiones de TERMINAL: carpetas con nombre que agrupan sesiones.
/// Solo organizan la vista (las sesiones viven en el puente). Se guardan como JSON:
/// [{id, name, open, ids: [sessionId…]}]. Una sesión está en un proyecto como mucho.
class SessionProjects extends ChangeNotifier {
  List<Map<String, dynamic>> list = [];
  late final _prefs = SharedPreferencesAsync();

  Future<void> load() async {
    final raw = await _prefs.getString('session_projects');
    if (raw != null) {
      list = [
        for (final p in jsonDecode(raw) as List)
          {...p as Map<String, dynamic>, 'ids': List<String>.from(p['ids'] as List)},
      ];
      notifyListeners();
    }
  }

  void _save() {
    notifyListeners();
    _prefs.setString('session_projects', jsonEncode(list));
  }

  Map<String, dynamic>? byId(String id) => list.where((p) => p['id'] == id).firstOrNull;

  /// Proyecto que contiene la sesión [sid], o null.
  Map<String, dynamic>? of(String sid) => list.where((p) => (p['ids'] as List).contains(sid)).firstOrNull;

  List<String> idsOf(Map<String, dynamic> p) => p['ids'] as List<String>;

  /// Proyecto nuevo con las sesiones [ids] (salen de donde estaban). Devuelve su id.
  String create(String name, List<String> ids) {
    for (final s in ids) {
      _take(s);
    }
    final id = uuid4();
    list.add({
      'id': id,
      'name': name,
      'open': true,
      'ids': [...ids],
    });
    _save();
    return id;
  }

  void _take(String sid) {
    for (final p in list) {
      idsOf(p).remove(sid);
    }
  }

  /// Mete la sesión en el proyecto (la saca del anterior).
  void add(String project, String sid) {
    final p = byId(project);
    if (p == null || idsOf(p).contains(sid)) return;
    _take(sid);
    idsOf(p).add(sid);
    p['open'] = true;
    _save();
  }

  /// Saca la sesión de su proyecto: vuelve a la lista suelta.
  void remove(String sid) {
    _take(sid);
    _save();
  }

  void rename(String project, String name) {
    byId(project)?['name'] = name;
    _save();
  }

  void toggle(String project) {
    final p = byId(project);
    if (p == null) return;
    p['open'] = p['open'] != true;
    _save();
  }

  /// Borra el proyecto; sus sesiones quedan sueltas (no se borran).
  void delete(String project) {
    list.removeWhere((p) => p['id'] == project);
    _save();
  }
}

final projects = SessionProjects()..load();
