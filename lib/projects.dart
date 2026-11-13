import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'claude.dart' show uuid4;

/// Proyectos de la lista de sesiones de TERMINAL: carpetas con nombre que agrupan sesiones.
/// Solo organizan la vista (las sesiones viven en el puente). Se guardan como JSON:
/// [{id, name, open, ids: [sessionId…]}]. Una sesión está en un proyecto como mucho.
class SessionProjects extends ChangeNotifier {
  List<Map<String, dynamic>> list = [];

  /// Orden manual de las sesiones sueltas (ids); las que no figuran van primero.
  List<String> order = [];
  late final _prefs = SharedPreferencesAsync();

  Future<void> load() async {
    final ord = await _prefs.getString('session_order');
    if (ord != null) order = List<String>.from(jsonDecode(ord) as List);
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
    _prefs.setString('session_order', jsonEncode(order));
  }

  /// Las sesiones sueltas [loose] en el orden manual (estable; las desconocidas van primero).
  List<Map<String, dynamic>> ordered(List<Map<String, dynamic>> loose) {
    final keyed = [for (var i = 0; i < loose.length; i++) (order.indexOf(loose[i]['id'] as String), i, loose[i])];
    keyed.sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
    return [for (final k in keyed) k.$3];
  }

  /// Pone [sid] justo antes/después de [target], sin agrupar. Si [target] está en un proyecto,
  /// [sid] entra a ese proyecto en esa posición; si no, queda suelta en el orden de [loose]
  /// (ids de las sueltas, en el orden en que se ven).
  void move(String sid, String target, {required bool after, required List<String> loose}) {
    if (sid == target) return;
    _take(sid);
    final p = of(target);
    if (p != null) {
      final ids = idsOf(p);
      ids.insert(ids.indexOf(target) + (after ? 1 : 0), sid);
    } else {
      final o = [...loose]..remove(sid);
      final at = o.indexOf(target);
      o.insert(at < 0 ? o.length : at + (after ? 1 : 0), sid);
      order = o;
    }
    _save();
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
