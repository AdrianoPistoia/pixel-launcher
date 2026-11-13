import 'dart:io';
import 'dart:math';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'apps.dart';
import 'claude.dart';
import 'files.dart';
import 'pad.dart';
import 'projects.dart';
import 'tabs.dart';
import 'ui.dart';
import 'utilities.dart';
import 'views.dart';

// Pestaña TERMINAL (docs/terminal.md): Claude Code (chat), claude.ai / app oficial, y la búsqueda
// de apps de antes. La vista, la sesión y su carpeta se guardan en la config de la pestaña.

const terminalViews = {'buscar': 'buscar apps', 'chat': 'Claude Code', 'app': 'claude.ai'};

/// Pasa a la vista siguiente (Y o menú de la pestaña). Sin 'view' es el chat de Claude.
Future<void> nextTerminalView(int tab) {
  final keys = terminalViews.keys.toList();
  final now = keys.indexOf(tabStore.tabs[tab]['view'] as String? ?? 'chat');
  return tabStore.setConfig(tab, {'view': keys[(now + 1) % keys.length]});
}

const _claudeApp = 'com.anthropic.claude';

enum Msg { user, claude, tool, status, file }

/// Una línea del chat: tipo, texto y el detalle que se abre al tocarla (tools y avisos).
typedef Line = (Msg, String, String?);

/// Archivos que Claude escribió con Write y salieron bien (ruta tal cual, para pedirla al puente).
String? _writtenFile(Map b, Map? r) {
  if (b['name'] != 'Write' || r == null || r['is_error'] == true) return null;
  final input = b['input'];
  final p = input is Map ? input['file_path'] : null;
  return p is String && p.isNotEmpty ? p : null;
}

/// Qué mostrar de los eventos de stream-json de una sesión. Cada tool es una línea con su resultado
/// adentro: `~` corriendo, `>` bien, `!` error. Pensamientos, system y rate limits no se muestran.
List<Line> chatLines(List<Map> events, String cwd) {
  String rel(String s) => s.startsWith('$cwd/') ? s.substring(cwd.length + 1) : s;
  final results = {
    for (final ev in events)
      for (final b in blocksOf(ev))
        if (b['type'] == 'tool_result') '${b['tool_use_id']}': b,
  };
  // avisos que Claude Code mete como mensajes del usuario (p. ej. terminó una tarea en segundo plano)
  Line say(Msg who, String t) => who == Msg.user && t.startsWith('<')
      ? (
          Msg.status,
          '· ${RegExp(r'<summary>(.*?)</summary>', dotAll: true).firstMatch(t)?[1] ?? 'aviso de Claude Code'}',
          _plain(t),
        )
      : (who, t, null);
  return [
    for (final ev in events)
      ...switch (ev['type']) {
        'user' || 'assistant' => () {
          final who = ev['type'] == 'user' ? Msg.user : Msg.claude;
          final c = (ev['message'] as Map?)?['content'];
          if (c is String) return [say(who, c)];
          return [
            for (final b in blocksOf(ev))
              if (b['type'] == 'text')
                say(who, '${b['text']}')
              else if (b['type'] == 'tool_use') ...[
                _tool(b, results['${b['id']}'], rel),
                if (_writtenFile(b, results['${b['id']}']) case final f?) (Msg.file, f, '${b['id']}'),
              ],
          ];
        }(),
        'result' => [_result(ev)],
        _ => const <Line>[],
      },
  ];
}

/// Lista de tareas de Claude: el último TodoWrite de la sesión, [{content, status, activeForm}].
List<Map> latestTodos(List<Map> events) {
  for (final ev in events.reversed) {
    for (final b in blocksOf(ev).toList().reversed) {
      if (b['type'] != 'tool_use' || b['name'] != 'TodoWrite') continue;
      final input = b['input'];
      final todos = input is Map ? input['todos'] : null;
      if (todos is List) return todos.whereType<Map>().toList();
    }
  }
  return const [];
}

Line _tool(Map b, Map? r, String Function(String) rel) {
  final input = b['input'] is Map ? b['input'] as Map : const {};
  final mark = r == null ? '~' : (r['is_error'] == true ? '!' : '>');
  var out = r == null ? '(corriendo)' : _plain(r['content']);
  if (out.length > 6000) out = '…${out.substring(out.length - 6000)}'; // ponytail: solo la cola de salidas enormes
  // la razón (3–6 palabras que pide el puente) va al frente: se lee aunque el comando se corte
  final why = input['description'] is String ? (input['description'] as String).trim() : '';
  return (
    Msg.tool,
    '$mark ${why.isEmpty ? '' : '$why · '}${bareTool('${b['name']}')} ${rel(_target(input))}',
    '${[for (final e in input.entries) '${e.key}: ${e.value}'].join('\n')}\n\n── resultado ──\n$out',
  );
}

Line _result(Map ev) {
  final secs = (ev['duration_ms'] as num? ?? 0) / 1000;
  final cost = ev['total_cost_usd'] as num?;
  final what = ev['subtype'] == 'error_during_execution'
      ? 'detenido'
      : ev['is_error'] == true
      ? 'error'
      : 'listo';
  return (
    Msg.status,
    '— $what · ${secs.toStringAsFixed(1)} s${cost == null ? '' : ' · US\$ ${cost.toStringAsFixed(3)}'}',
    null,
  );
}

/// Parte un texto markdown en prosa y bloques de código (```): (esCódigo, texto). Un bloque sin
/// cerrar (respuesta a medio llegar) es código igual.
List<(bool, String)> mdBlocks(String md) {
  final out = <(bool, String)>[];
  final parts = md.split(RegExp(r'^ *```[^\n]*\n?', multiLine: true));
  for (final (i, p) in parts.indexed) {
    final t = i.isOdd ? p.replaceFirst(RegExp(r'\n$'), '') : p.trim();
    if (t.isNotEmpty) out.add((i.isOdd, t));
  }
  return out;
}

/// Una línea de prosa: títulos (#), viñetas (- / *), **negrita** y `código` en color.
TextSpan mdLine(String line) {
  final h = RegExp(r'^#{1,6} +').firstMatch(line);
  if (h != null)
    return TextSpan(
      text: line.substring(h.end),
      style: TextStyle(color: Px.accent),
    );
  final text = line.replaceFirstMapped(RegExp(r'^( *)[-*] +'), (m) => '${m[1]}• ');
  final spans = <TextSpan>[];
  var at = 0;
  for (final m in RegExp(r'\*\*(.+?)\*\*|`([^`]+)`').allMatches(text)) {
    spans
      ..add(TextSpan(text: text.substring(at, m.start)))
      ..add(
        TextSpan(
          text: m[1] ?? m[2],
          style: TextStyle(color: m[1] != null ? Px.accent : Px.dimText),
        ),
      );
    at = m.end;
  }
  return TextSpan(
    children: [
      ...spans,
      TextSpan(text: text.substring(at)),
    ],
  );
}

/// Sobre qué actúa una tool, en una línea: archivo, comando, patrón, dirección…
String _target(Object? input) {
  if (input is! Map) return '';
  for (final k in ['file_path', 'notebook_path', 'command', 'cmd', 'pattern', 'path', 'url', 'query', 'package']) {
    if (input[k] != null) return '${input[k]}'.split('\n').first;
  }
  return '';
}

/// Texto de un tool_result (string o bloques), sin las etiquetas tipo `<tool_use_error>`.
String _plain(Object? content) =>
    (content is List ? content.map((b) => b is Map ? b['text'] ?? '' : '').join(' ') : '$content')
        .replaceAll(RegExp('<[^>]+>'), '')
        .trim();

class TerminalTab extends StatefulWidget {
  const TerminalTab(this.tab, {super.key});

  final int tab;

  @override
  State<TerminalTab> createState() => _TerminalTabState();
}

class _TerminalTabState extends State<TerminalTab> with TickerProviderStateMixin {
  // mientras se arrastra una sesión, las demás hacen sube-y-baja (giran sobre su centro) sin parar;
  // ease entra y sale suave: al soltar el vaivén se asienta solo en vez de cortarse
  late final wiggle = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  late final ease = AnimationController(vsync: this, duration: const Duration(milliseconds: 180));
  String? dragId; // sesión que se está arrastrando
  final scroll = ScrollController();
  int seen = 0; // eventos ya mostrados: si llegan más, baja al final
  bool todosOpen = true; // el panel de tareas del chat, desplegado o solo la barra
  bool showSteps = false; // los pasos de instalación con el puente andando (LOGIN, Shizuku…)

  @override
  void initState() {
    super.initState();
    bridge.connect(); // sin arrancar nada: si el puente no está, se ve la lista de pasos
  }

  @override
  void dispose() {
    scroll.dispose();
    wiggle.dispose();
    ease.dispose();
    super.dispose();
  }

  void set(Map<String, dynamic> values) => tabStore.setConfig(widget.tab, values);

  Widget _hint(String text) => Text(
    text,
    style: Px.text.copyWith(fontSize: Px.sz(17), color: Px.dimText),
  );

  Widget get _viewHint => _hint('${padLabel(PadButton.view)} cambia de vista');

  /// Corre una acción de los pasos y muestra el error, si hay.
  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      bridge.say(e is PlatformException ? e.message ?? e.code : '$e');
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([tabStore, bridge, store, fileOpeners, projects]),
    builder: (context, _) {
      if (widget.tab >= tabStore.tabs.length) return const SizedBox();
      final c = tabStore.tabs[widget.tab];
      final session = c['session'] as String?;
      return Focus(
        skipTraversal: true, // solo escucha Y: que el D-pad no se detenga en este nodo
        onKeyEvent: (_, e) {
          if (e is! KeyDownEvent || e.logicalKey != padKey(PadButton.view)) return KeyEventResult.ignored;
          nextTerminalView(widget.tab);
          return KeyEventResult.handled;
        },
        child: switch (c['view'] ?? 'chat') {
          'buscar' => const TerminalPage(),
          'app' => _app(c),
          _ when !bridge.connected || showSteps => _setup(),
          _ when session == null => _sessions(),
          _ => _chat(session, c['cwd'] as String? ?? '/root'),
        },
      );
    },
  );

  Widget _setup() {
    final steps = [
      bridge.connected
          ? (
              'REINICIAR PUENTE',
              'Carga el puente de esta versión del launcher. Corta las sesiones; siguen con el próximo mensaje.',
              () => bridge.connectOrStart(restart: true),
            )
          : ('CONECTAR', 'Conecta con el puente en Termux; si no está corriendo, lo arranca.', bridge.connectOrStart),
      ('INSTALAR ENTORNO', 'Debian, node, git y Claude Code dentro de Termux. Una sola vez.', setupTermux),
      (
        'INSTALAR TOOLCHAIN',
        'Lo anterior más JDK, Android SDK y Flutter, para compilar el launcher acá.',
        () => setupTermux(toolchain: true),
      ),
      ('LOGIN', 'Abre Claude en Termux para hacer /login con tu cuenta.', loginClaude),
      (
        'PERMISO SHIZUKU',
        'Deja que Claude cambie ajustes e instale apps, y apaga el límite de procesos de Android 12+ '
            '(si no, corta las sesiones largas). Abrí Shizuku antes.',
        () async {
          if (await native.invokeMethod<bool>('shizukuPermission') != true) {
            return bridge.say('Shizuku no autorizó: ¿está corriendo?');
          }
          // Android 13+: el ajuste; Android 12: el límite (GMS lo puede pisar al rato)
          await shizuku(
            'settings put global settings_enable_monitor_phantom_procs false; '
            'device_config put activity_manager max_phantom_processes 2147483647',
          );
          bridge.say('Shizuku autorizado y límite de procesos apagado.');
        },
      ),
    ];
    return ListView(
      padding: const EdgeInsets.only(right: Px.unit * 2, bottom: Px.unit * 2),
      children: [
        if (bridge.connected) ...[
          PixelTile(label: '< VOLVER', onTap: () => setState(() => showSteps = false)),
          const SizedBox(height: 8),
        ],
        _hint('Antes: Termux de F-Droid con allow-external-apps=true, y Shizuku.'),
        for (final (i, (label, about, action)) in steps.indexed) ...[
          const SizedBox(height: 8),
          PixelTile(autofocus: i == 0, label: label, onTap: () => _run(action)),
          _hint(about),
        ],
        const SizedBox(height: 8),
        if (bridge.status != null) Text(bridge.status!, style: Px.text.copyWith(color: Px.accent)),
      ],
    );
  }

  static const _todoStatus = {'completed': 'hecha', 'in_progress': 'en curso', 'pending': 'pendiente'};

  /// Tareas de Claude (TodoWrite): barra de avance y pasos en línea de tiempo; tocar uno abre su detalle.
  Widget _todos(List<Map> todos) {
    final done = todos.where((t) => t['status'] == 'completed').length;
    return Container(
      margin: const EdgeInsets.only(bottom: 8, right: Px.unit * 2),
      padding: const EdgeInsets.all(8),
      decoration: Px.box(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PixelTile(
            label: 'TAREAS $done/${todos.length} ${todosOpen ? '-' : '+'}',
            onTap: () => setState(() => todosOpen = !todosOpen),
          ),
          const SizedBox(height: 6),
          Container(
            height: 16,
            padding: const EdgeInsets.all(Px.unit),
            decoration: BoxDecoration(
              border: Border.all(color: Px.dim, width: Px.unit * 2),
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: done / todos.length,
                heightFactor: 1,
                child: ColoredBox(color: Px.accent),
              ),
            ),
          ),
          if (todosOpen) ...[
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final (i, t) in todos.indexed)
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: 22,
                            child: Column(
                              children: [
                                Container(
                                  width: 14,
                                  height: 14,
                                  margin: const EdgeInsets.only(top: 6),
                                  decoration: BoxDecoration(
                                    color: t['status'] == 'completed' ? Px.accent : Px.bg,
                                    border: Border.all(
                                      color: switch (t['status']) {
                                        'completed' => Px.accent,
                                        'in_progress' => Px.hi,
                                        _ => Px.dim,
                                      },
                                      width: Px.unit * 2,
                                    ),
                                  ),
                                ),
                                if (i < todos.length - 1)
                                  Expanded(
                                    child: Container(
                                      width: Px.unit * 2,
                                      color: t['status'] == 'completed' ? Px.accent : Px.dim,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: PixelTile(
                                maxLines: 2,
                                selected: t['status'] == 'in_progress',
                                label:
                                    '${t['status'] == 'in_progress' ? (t['activeForm'] ?? t['content']) : t['content']}',
                                onTap: () => _todoDetail(i, todos),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _todoDetail(int i, List<Map> todos) {
    final t = todos[i];
    showPixelDialog<void>(
      context,
      'Tarea ${i + 1} de ${todos.length}',
      (c) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${t['content']}', style: Px.text),
          const SizedBox(height: 8),
          _hint('Estado: ${_todoStatus[t['status']] ?? t['status']}'),
          if (t['activeForm'] != null && t['activeForm'] != t['content']) _hint('Mientras corre: ${t['activeForm']}'),
          const SizedBox(height: 8),
          PixelTile(autofocus: true, label: 'OK', onTap: () => Navigator.pop(c)),
        ],
      ),
    );
  }

  /// Uso del plan: 5 horas, semanal y Fable. Claude Code informa el límite (`rate_limit_event`) mientras
  /// trabaja, así que se muestra lo último que llegó; se actualiza solo si Claude responde con el diálogo abierto.
  void _usage() => showPixelDialog<void>(
    context,
    'Uso del plan',
    (c) => ListenableBuilder(
      listenable: bridge,
      builder: (c, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (name, key) in const [
            ('Últimas 5 horas', 'five_hour'),
            ('Semanal', 'seven_day'),
            ('Fable', 'fable'),
          ])
            _usageRow(name, usageOf(bridge.usage, key)),
          _hint('Se actualiza cuando Claude responde. Sin datos = todavía no mandó el aviso de límite.'),
          const SizedBox(height: 8),
          PixelTile(autofocus: true, label: 'CERRAR', onTap: () => Navigator.pop(c)),
        ],
      ),
    ),
  );

  Widget _usageRow(String name, Map<String, dynamic>? info) {
    final pct = info == null ? null : usagePct(info);
    final reset = info == null ? null : usageReset(info, DateTime.now());
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(name, style: Px.text)),
              Text(
                info == null ? 'sin datos' : (pct == null ? '${info['status'] ?? '?'}' : '${pct.round()}%'),
                style: Px.text.copyWith(color: Px.accent),
              ),
            ],
          ),
          if (pct != null)
            Container(
              height: 16,
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.all(Px.unit),
              decoration: BoxDecoration(
                border: Border.all(color: Px.dim, width: Px.unit * 2),
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: pct / 100,
                  heightFactor: 1,
                  child: ColoredBox(color: pct > 85 ? Colors.redAccent : (pct > 60 ? Colors.amber : Px.accent)),
                ),
              ),
            ),
          if (reset != null) _hint('se reinicia $reset'),
        ],
      ),
    );
  }

  /// Mensaje para Claude: caja grande de varias líneas, con ADJUNTAR (archivos, fotos, capturas, PDFs).
  /// Los adjuntos quedan en `bridge.drafts[id]`. Devuelve el texto, o null si se cancela.
  Future<String?> _compose(String id) {
    final input = TextEditingController();
    final files = bridge.drafts[id] ??= [];
    return showPixelDialog<String>(
      context,
      'Mensaje para Claude',
      (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: input,
              autofocus: true,
              style: Px.text,
              decoration: Px.input('escribí acá...'),
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              minLines: 8,
              maxLines: 14,
            ),
            for (final f in files)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: PixelTile(
                  label: '${f.name} (${_size(f.size)}) · QUITAR',
                  onTap: () {
                    File(f.path).delete().ignore();
                    setLocal(() => files.remove(f));
                  },
                ),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                PixelTile(
                  label: 'ADJUNTAR',
                  onTap: () async {
                    final picked = await pickAttachments();
                    setLocal(() => files.addAll(picked));
                  },
                ),
                PixelTile(label: 'ENVIAR', onTap: () => Navigator.pop(ctx, input.text)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _size(int b) => b >= 1 << 20 ? '${(b / (1 << 20)).toStringAsFixed(1)} MB' : '${(b / 1024).ceil()} KB';

  Future<void> _newSession({String? project}) async {
    final cwd = (await askText(context, 'Carpeta de la sesión', initial: '/root'))?.trim();
    if (cwd == null || cwd.isEmpty) return;
    final id = uuid4();
    if (project != null) projects.add(project, id);
    set({'session': id, 'cwd': cwd});
  }

  /// id = empieza a arrastrar esa sesión; null = soltó (se llama desde varios lados, es idempotente).
  void _drag(String? id) {
    if (!mounted || dragId == id) return;
    setState(() => dragId = id);
    if (id != null) {
      wiggle.repeat();
      ease.forward();
    } else {
      ease.reverse().whenComplete(() {
        if (dragId == null) wiggle.stop();
      });
    }
  }

  String _titleOf(String id) {
    final s = bridge.sessions.where((s) => s['id'] == id).firstOrNull;
    return '${s?['title'] ?? '(sin título)'}';
  }

  /// Pide el nombre y crea un proyecto con esas sesiones.
  Future<void> _newProject(List<String> ids) async {
    final name = (await askText(context, 'Nombre del proyecto', initial: 'Proyecto'))?.trim();
    if (name == null || name.isEmpty) return;
    projects.create(name, ids);
  }

  /// Soltar [dragged] sobre la sesión [target]: si está en un proyecto se suma a él, si no se arma uno.
  void _dropOnSession(String dragged, String target) {
    final p = projects.of(target);
    if (p != null) {
      projects.add(p['id'] as String, dragged);
    } else {
      _newProject([target, dragged]);
    }
  }

  void _sessionMenu(Map<String, dynamic> s) {
    final id = s['id'] as String;
    final inProject = projects.of(id);
    showPixelMenu(context, 'Sesión', [
      if (inProject != null) ('Sacar de "${inProject['name']}"', () => projects.remove(id)),
      for (final p in projects.list)
        if (p != inProject) ('Mover a "${p['name']}"', () => projects.add(p['id'] as String, id)),
      ('Nuevo proyecto con esta sesión', () => _newProject([id])),
      ('Terminar proceso', () => bridge.close(id)),
      (
        'Borrar sesión',
        () => showPixelMenu(context, '¿Borrar "${s['title'] ?? '(sin título)'}"? No se puede deshacer', [
          ('Cancelar', () {}),
          (
            'Sí, borrar',
            () {
              projects.remove(id);
              bridge.delete(id);
            },
          ),
        ]),
      ),
    ]);
  }

  void _projectMenu(Map<String, dynamic> p) {
    final id = p['id'] as String;
    showPixelMenu(context, 'Proyecto "${p['name']}"', [
      ('Nueva sesión adentro', () => _newSession(project: id)),
      (
        'Renombrar',
        () async {
          final name = (await askText(context, 'Nombre del proyecto', initial: '${p['name']}'))?.trim();
          if (name != null && name.isNotEmpty) projects.rename(id, name);
        },
      ),
      (
        'Borrar proyecto',
        () => showPixelMenu(context, '¿Borrar "${p['name']}"? Las sesiones no se borran, quedan sueltas', [
          ('Cancelar', () {}),
          ('Sí, borrar proyecto', () => projects.delete(id)),
        ]),
      ),
    ]);
  }

  static const _folder = [
    '........',
    '.###....',
    '########',
    '#......#',
    '#......#',
    '#......#',
    '########',
    '........',
  ];

  /// Sube-y-baja: rotación rígida sobre el centro (un lado menor sube y el otro baja), ±1,6°.
  /// Filas vecinas en contrafase. Siempre envuelve (sin cambiar el árbol: si no, el Draggable se
  /// recrea al empezar el arrastre). [i] < 0 = la fila arrastrada, quieta.
  Widget _skewed(Widget child, int i) => AnimatedBuilder(
    animation: Listenable.merge([wiggle, ease]),
    builder: (_, c) => ease.value == 0 || i < 0
        ? c!
        : Transform.rotate(
            angle:
                sin(wiggle.value * 2 * pi + (i.isEven ? 0 : pi)) *
                1.6 *
                pi /
                180 *
                Curves.easeOut.transform(ease.value),
            child: c,
          ),
    child: child,
  );

  Widget _projectHeader(Map<String, dynamic> p, int i, int count) {
    final id = p['id'] as String;
    final open = p['open'] == true;
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => !projects.idsOf(p).contains(d.data),
      onAcceptWithDetails: (d) => projects.add(id, d.data),
      builder: (_, over, _) => _skewed(
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: PixelTile(
            leading: const PixelGlyph(_folder, size: Px.icon * 0.75),
            label: '${p['name']} ($count) ${open ? 'v' : '>'}',
            selected: over.isNotEmpty,
            onTap: () => projects.toggle(id),
            onLongPress: () => _projectMenu(p),
          ),
        ),
        i,
      ),
    );
  }

  /// Fila de una sesión: mantener apretado y mover = arrastrar (sobre otra sesión arma proyecto,
  /// sobre un proyecto la mete); mantener sin mover (o el botón de menú) abre el menú.
  Widget _sessionRow(Map<String, dynamic> s, int i, {bool indent = false}) {
    final id = s['id'] as String;
    final tile = PixelTile(
      maxLines: 2,
      label: '${s['running'] == true ? '* ' : ''}${s['title'] ?? '(sin título)'}\n${s['cwd']}',
      onTap: () => set({'session': id, 'cwd': s['cwd']}),
      onMenu: () => _sessionMenu(s),
    );
    return Padding(
      key: ValueKey(id), // que la fila no se recree si cambia de lugar (perdería el arrastre)
      padding: EdgeInsets.only(top: 4, left: indent ? Px.unit * 4 : 0),
      child: DragTarget<String>(
        onWillAcceptWithDetails: (d) => d.data != id,
        onAcceptWithDetails: (d) => _dropOnSession(d.data, id),
        builder: (_, over, _) => LayoutBuilder(
          builder: (context, box) {
            final shown = over.isEmpty
                ? tile
                : PixelTile(maxLines: 2, selected: true, label: 'Soltar acá: agrupar con esta sesión\n${_titleOf(id)}');
            Offset? from;
            return _skewed(
              LongPressDraggable<String>(
                data: id,
                delay: const Duration(milliseconds: 300),
                hapticFeedbackOnStart: true,
                onDragStarted: () {
                  from = (context.findRenderObject() as RenderBox?)?.localToGlobal(Offset.zero);
                  _drag(id);
                },
                onDragEnd: (d) {
                  _drag(null);
                  // se soltó sin mover: era un long-press común, abre el menú
                  if (!d.wasAccepted && from != null && (d.offset - from!).distance < 12) _sessionMenu(s);
                },
                feedback: Material(
                  type: MaterialType.transparency,
                  child: SizedBox(
                    width: box.maxWidth,
                    child: Transform.rotate(
                      angle: -0.03,
                      child: PixelTile(
                        maxLines: 2,
                        selected: true,
                        label: '${s['title'] ?? '(sin título)'}\n${s['cwd']}',
                      ),
                    ),
                  ),
                ),
                childWhenDragging: Opacity(opacity: 0.3, child: tile),
                child: shown,
              ),
              dragId == id ? -1 : i,
            );
          },
        ),
      ),
    );
  }

  Widget _sessions() {
    final byId = {for (final s in bridge.sessions) s['id'] as String: s};
    final grouped = {for (final p in projects.list) ...projects.idsOf(p)};
    var i = 0;
    return Listener(
      // red de seguridad: sea como sea que termine el gesto, el vaivén se apaga
      onPointerUp: (_) => _drag(null),
      onPointerCancel: (_) => _drag(null),
      child: ListView(
        padding: const EdgeInsets.only(right: Px.unit * 2, bottom: Px.unit * 2),
        children: [
          PixelTile(autofocus: true, label: '+ NUEVA SESIÓN', onTap: _newSession),
          const SizedBox(height: 4),
          PixelTile(label: 'INSTALACIÓN Y LOGIN', onTap: () => setState(() => showSteps = true)),
          // mientras se arrastra una sesión de un proyecto: soltarla acá la saca
          if (dragId != null && projects.of(dragId!) != null)
            DragTarget<String>(
              onAcceptWithDetails: (d) => projects.remove(d.data),
              builder: (_, over, _) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: PixelTile(selected: over.isNotEmpty, label: 'Soltar acá: sacar del proyecto'),
              ),
            ),
          for (final p in projects.list) ...[
            _projectHeader(p, i++, projects.idsOf(p).where(byId.containsKey).length),
            if (p['open'] == true)
              for (final id in projects.idsOf(p))
                if (byId[id] != null) _sessionRow(byId[id]!, i++, indent: true),
          ],
          for (final s in bridge.sessions)
            if (!grouped.contains(s['id'])) _sessionRow(s, i++),
          const SizedBox(height: 8),
          if (bridge.status != null) Text(bridge.status!, style: Px.text.copyWith(color: Px.accent)),
          _hint(
            '* = corriendo · mantené y arrastrá una sesión sobre otra para armar un proyecto · ${padLabel(PadButton.menu)} menú',
          ),
          _viewHint, // el único lugar del aviso de Y
        ],
      ),
    );
  }

  /// Respuesta de Claude: prosa con formato y bloques de código en recuadro, con COPIAR adentro.
  Widget _markdown(String md) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (code, t) in mdBlocks(md))
        code
            ? Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.all(8),
                decoration: Px.box(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: PixelTile(
                        label: 'COPIAR',
                        // Android 13+ ya avisa que se copió
                        onTap: () => Clipboard.setData(ClipboardData(text: t)),
                      ),
                    ),
                    const SizedBox(height: 4),
                    // largo: se desliza de costado en vez de partir los comandos
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Text(t, style: Px.code),
                    ),
                  ],
                ),
              )
            : Text.rich(
                TextSpan(
                  children: [
                    for (final (i, l) in t.split('\n').indexed) ...[if (i > 0) const TextSpan(text: '\n'), mdLine(l)],
                  ],
                ),
                style: Px.text,
              ),
    ],
  );

  /// Comando y salida completos de una tool (o el texto de un aviso).
  void _detail(String title, String text) => showPixelDialog(
    context,
    title,
    (ctx) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(text, style: Px.text.copyWith(fontSize: Px.sz(17))),
        const SizedBox(height: 8),
        PixelTile(autofocus: true, label: 'CERRAR', onTap: () => Navigator.pop(ctx)),
      ],
    ),
  );

  Widget _chat(String id, String cwd) {
    bridge.open(id, cwd); // una vez por conexión; no notifica
    final events = bridge.events[id] ?? [];
    final lines = [...chatLines(events, cwd), if (bridge.live[id] case final t? when t.isNotEmpty) (Msg.claude, t, null)];
    final todos = latestTodos(events);
    final auto = tabStore.tabs[widget.tab]['auto'] == true;
    if (events.length != seen) {
      seen = events.length;
      // la lista va al revés: 0 es el final
      WidgetsBinding.instance.addPostFrameCallback((_) => scroll.hasClients ? scroll.jumpTo(0) : null);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            PixelTile(
              label: '< SESIONES',
              onTap: () {
                set({'session': null});
                bridge.refreshSessions();
              },
            ),
            const SizedBox(width: 8),
            Expanded(child: _hint(cwd)),
          ],
        ),
        const SizedBox(height: 8),
        if (todos.isNotEmpty) _todos(todos),
        Expanded(
          child: ListView.separated(
            controller: scroll,
            reverse: true,
            padding: const EdgeInsets.only(right: Px.unit * 2, bottom: Px.unit * 2),
            itemCount: lines.length,
            separatorBuilder: (_, _) => const SizedBox(height: 4),
            itemBuilder: (context, i) => switch (lines[lines.length - 1 - i]) {
              (Msg.status, final t, null) => _hint(t),
              // una tool corriendo (~) late mientras la sesión siga en un turno; si se cortó, queda como interrumpida (×)
              (Msg.status || Msg.tool, final t, final d) => PixelTile(
                label: t.startsWith('~ ') && !bridge.busy.contains(id) ? '× ${t.substring(2)}' : t,
                pulse: t.startsWith('~ ') && bridge.busy.contains(id),
                onTap: d == null ? null : () => _detail(t, d),
              ),
              // mis mensajes: pegados a la derecha, con fondo celeste (enfocables para bajar con el D-pad)
              // archivo generado: tocar abre con la última app de su tipo; mantener (o menú) = elegir otra
              (Msg.file, final t, final id) => FileCard(path: t, id: id ?? t),
              (Msg.user, final t, _) => Align(
                alignment: Alignment.centerRight,
                child: LayoutBuilder(
                  builder: (_, box) => ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: box.maxWidth * 0.85),
                    child: Focus(
                      child: Builder(
                        builder: (ctx) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: Px.bubble(focused: Focus.of(ctx).hasFocus),
                          child: Text(t, style: Px.text),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // la respuesta de Claude, entera y sin marco: es lo que se lee
              // (enfocable igual, para bajar con el D-pad; el marco aparece solo con foco)
              (_, final t, _) => Focus(
                child: Builder(
                  builder: (ctx) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: Focus.of(ctx).hasFocus ? Px.box() : null,
                    child: _markdown(t),
                  ),
                ),
              ),
            },
          ),
        ),
        const SizedBox(height: 8),
        if (bridge.status != null) Text(bridge.status!, style: Px.text.copyWith(color: Px.accent)),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            PixelTile(
              autofocus: true,
              // mientras Claude responde no se escribe ni se manda otro mensaje (DETENER lo corta)
              label: bridge.busy.contains(id) ? 'RESPONDIENDO…' : 'ESCRIBIR',
              pulse: bridge.busy.contains(id),
              onTap: bridge.busy.contains(id) ? null : () async {
                final t = (await _compose(id))?.trim();
                final files = List<Attachment>.of(bridge.drafts.remove(id) ?? []);
                if (t != null && (t.isNotEmpty || files.isNotEmpty)) {
                  bridge.send(id, cwd, t, files: files);
                } else {
                  // se canceló: los archivos quedan para el próximo mensaje
                  if (files.isNotEmpty) bridge.drafts[id] = files;
                }
              },
            ),
            if (bridge.busy.contains(id)) PixelTile(label: 'DETENER', onTap: () => bridge.stop(id)),
            PixelTile(label: 'USO', onTap: _usage),
            // modo auto: el MCP permite todo sin preguntar (incluye instalar apps y Shizuku)
            PixelTile(label: auto ? 'AUTO: SÍ' : 'AUTO: NO', selected: auto, onTap: () => set({'auto': !auto})),
          ],
        ),
      ],
    );
  }

  /// claude.ai adentro de la pestaña (la web de las utilidades) y accesos a la app oficial:
  /// Android no deja meter la interfaz de otra app.
  Widget _app(Config c) {
    c['url'] ??= 'https://claude.ai/new'; // se guarda con el próximo cambio de pestañas
    final installed = store.apps.any((a) => a.packageName == _claudeApp);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (installed) ...[
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              PixelTile(autofocus: true, label: 'ABRIR APP OFICIAL', onTap: () => store.launch(_claudeApp)),
              PixelTile(
                label: 'MANDAR A LA APP',
                onTap: () async {
                  final t = (await askText(context, 'Mandar a Claude'))?.trim();
                  if (t == null || t.isEmpty) return;
                  await AndroidIntent(
                    action: 'android.intent.action.SEND',
                    package: _claudeApp,
                    type: 'text/plain',
                    arguments: {'android.intent.extra.TEXT': t},
                  ).launch();
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        Expanded(child: WebUtil(c)),
      ],
    );
  }
}
