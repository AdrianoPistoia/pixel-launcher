import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'apps.dart';
import 'claude.dart';
import 'pad.dart';
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

enum Msg { user, claude, tool, status }

/// Una línea del chat: tipo, texto y el detalle que se abre al tocarla (tools y avisos).
typedef Line = (Msg, String, String?);

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
              else if (b['type'] == 'tool_use')
                _tool(b, results['${b['id']}'], rel),
          ];
        }(),
        'result' => [_result(ev)],
        _ => const <Line>[],
      },
  ];
}

Line _tool(Map b, Map? r, String Function(String) rel) {
  final input = b['input'] is Map ? b['input'] as Map : const {};
  final mark = r == null ? '~' : (r['is_error'] == true ? '!' : '>');
  var out = r == null ? '(corriendo)' : _plain(r['content']);
  if (out.length > 6000) out = '…${out.substring(out.length - 6000)}'; // ponytail: solo la cola de salidas enormes
  return (
    Msg.tool,
    '$mark ${bareTool('${b['name']}')} ${rel(_target(input))}',
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

class _TerminalTabState extends State<TerminalTab> {
  final scroll = ScrollController();
  int seen = 0; // eventos ya mostrados: si llegan más, baja al final
  bool showSteps = false; // los pasos de instalación con el puente andando (LOGIN, Shizuku…)

  @override
  void initState() {
    super.initState();
    bridge.connect(); // sin arrancar nada: si el puente no está, se ve la lista de pasos
  }

  @override
  void dispose() {
    scroll.dispose();
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
    listenable: Listenable.merge([tabStore, bridge, store]),
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
        _viewHint,
      ],
    );
  }

  Future<void> _newSession() async {
    final cwd = (await askText(context, 'Carpeta de la sesión', initial: '/root'))?.trim();
    if (cwd == null || cwd.isEmpty) return;
    set({'session': uuid4(), 'cwd': cwd});
  }

  Widget _sessions() => ListView(
    padding: const EdgeInsets.only(right: Px.unit * 2, bottom: Px.unit * 2),
    children: [
      PixelTile(autofocus: true, label: '+ NUEVA SESIÓN', onTap: _newSession),
      const SizedBox(height: 4),
      PixelTile(label: 'INSTALACIÓN Y LOGIN', onTap: () => setState(() => showSteps = true)),
      for (final s in bridge.sessions)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: PixelTile(
            maxLines: 2,
            label: '${s['running'] == true ? '* ' : ''}${s['title'] ?? '(sin título)'}\n${s['cwd']}',
            onTap: () => set({'session': s['id'], 'cwd': s['cwd']}),
            onLongPress: () =>
                showPixelMenu(context, 'Sesión', [('Terminar proceso', () => bridge.close(s['id'] as String))]),
          ),
        ),
      const SizedBox(height: 8),
      if (bridge.status != null) Text(bridge.status!, style: Px.text.copyWith(color: Px.accent)),
      _hint('* = corriendo · ${padLabel(PadButton.menu)} menú de la sesión'),
      _viewHint,
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
    final lines = chatLines(events, cwd);
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
        Expanded(
          child: ListView.separated(
            controller: scroll,
            reverse: true,
            padding: const EdgeInsets.only(right: Px.unit * 2, bottom: Px.unit * 2),
            itemCount: lines.length,
            separatorBuilder: (_, _) => const SizedBox(height: 4),
            itemBuilder: (context, i) => switch (lines[lines.length - 1 - i]) {
              (Msg.status, final t, null) => _hint(t),
              (Msg.status || Msg.tool, final t, final d) => PixelTile(
                label: t,
                onTap: d == null ? null : () => _detail(t, d),
              ),
              (Msg.user, final t, _) => PixelTile(label: '» $t', maxLines: null),
              // la respuesta de Claude, entera y sin marco: es lo que se lee
              // (enfocable igual, para bajar con el D-pad; el marco aparece solo con foco)
              (_, final t, _) => Focus(
                child: Builder(
                  builder: (ctx) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: Focus.of(ctx).hasFocus ? Px.box() : null,
                    child: Text(t, style: Px.text),
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
              label: 'ESCRIBIR',
              onTap: () async {
                final t = (await askText(context, 'Mensaje para Claude'))?.trim();
                if (t != null && t.isNotEmpty) bridge.send(id, cwd, t);
              },
            ),
            if (bridge.busy.contains(id)) PixelTile(label: 'DETENER', onTap: () => bridge.stop(id)),
            // modo auto: el MCP permite todo sin preguntar (incluye instalar apps y Shizuku)
            PixelTile(label: auto ? 'AUTO: SÍ' : 'AUTO: NO', selected: auto, onTap: () => set({'auto': !auto})),
            _viewHint,
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
        _viewHint,
      ],
    );
  }
}
