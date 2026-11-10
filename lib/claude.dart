import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'apps.dart';
import 'pad.dart';
import 'tabs.dart';
import 'ui.dart';

// Claude Code en el teléfono (docs/terminal.md): cliente del puente de Termux, servidor MCP del
// launcher y política de permisos.

/// Para mostrar diálogos desde fuera del árbol (los pedidos de permiso del MCP).
final navigatorKey = GlobalKey<NavigatorState>();

final _rand = Random.secure();
String _hex(int bytes) => [for (var i = 0; i < bytes; i++) _rand.nextInt(256).toRadixString(16).padLeft(2, '0')].join();

String uuid4() {
  final h = _hex(16);
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-4${h.substring(13, 16)}-'
      '${'89ab'[_rand.nextInt(4)]}${h.substring(17, 20)}-${h.substring(20)}';
}

/// Token que comparten launcher, puente y MCP: se genera una vez y queda en prefs.
final Future<String> claudeToken = () async {
  final prefs = SharedPreferencesAsync();
  final t = await prefs.getString('claude_token');
  if (t != null) return t;
  final n = _hex(16);
  await prefs.setString('claude_token', n);
  return n;
}();

// ─── Termux ──────────────────────────────────────────────────────────────────

Future<void> _termux(List<String> args, {bool background = false}) async {
  if (await native.invokeMethod<bool>('termuxPermission') != true) {
    throw 'Falta el permiso "Ejecutar comandos en Termux".';
  }
  final err = await native.invokeMethod<String>('termux', {'args': args, 'background': background});
  if (err != null) throw err;
}

/// Arranca el puente en segundo plano (mata el anterior si había).
Future<void> startBridge() async => _termux([
  '-c',
  await rootBundle.loadString('termux/start.sh'),
  'start',
  await rootBundle.loadString('termux/bridge.js'),
  await claudeToken,
], background: true);

/// Instala Debian, node y Claude Code (con [toolchain], también JDK, Android SDK y Flutter) en una sesión visible.
Future<void> setupTermux({bool toolchain = false}) async => _termux([
  '-c',
  await rootBundle.loadString('termux/setup.sh'),
  'setup',
  await claudeToken,
  if (toolchain) '--toolchain',
]);

Future<void> loginClaude() => _termux(['-c', 'proot-distro login debian -- claude']);

// ─── Puente ──────────────────────────────────────────────────────────────────

/// Conexión con `bridge.js`: NDJSON por TCP. Las sesiones y sus eventos viven acá y no en la
/// pestaña, porque PageView destruye las páginas que no se ven.
class Bridge extends ChangeNotifier {
  Bridge() {
    // con un turno en curso, servicio en primer plano: si Android mata al launcher, el MCP (permisos) muere
    var alive = false;
    addListener(() {
      if (busy.isNotEmpty == alive) return;
      alive = !alive;
      native.invokeMethod('keepAlive', alive).ignore();
    });
  }

  Socket? _socket;
  bool get connected => _socket != null;
  List<Map<String, dynamic>> sessions = [];
  final events = <String, List<Map<String, dynamic>>>{}; // id → eventos de stream-json
  final busy = <String>{}; // sesiones con un turno en curso
  final approvedTurn = <String>{}; // sesiones con lo de bajo riesgo aprobado hasta el próximo mensaje
  final _open = <String, String>{}; // suscripciones id → cwd; se renuevan al reconectar
  String? status; // último aviso o error, para mostrar en la pestaña
  Future<bool>? _connecting;

  void say(String? s) {
    status = s;
    notifyListeners();
  }

  Future<bool> connect() => _connecting ??= _connect().whenComplete(() => _connecting = null);

  Future<bool> _connect() async {
    if (_socket != null) return true;
    try {
      final s = await Socket.connect(InternetAddress.loopbackIPv4, 8765, timeout: const Duration(seconds: 2));
      s.done.ignore(); // los errores de escritura llegan también por el stream
      s.writeln(jsonEncode({'token': await claudeToken}));
      _socket = s;
      utf8.decoder
          .bind(s)
          .transform(const LineSplitter())
          .listen(_line, onDone: _drop, onError: (_) => _drop(), cancelOnError: true);
      refreshSessions();
      for (final MapEntry(key: id, value: cwd) in _open.entries) {
        events[id] = [];
        _send({'op': 'open', 'id': id, 'cwd': cwd});
      }
      say(null);
      return true;
    } on SocketException {
      return false;
    }
  }

  /// Conecta; si el puente no corre (o [restart], para cargar un bridge.js nuevo), lo arranca en
  /// Termux y espera hasta 15 s. Reiniciar corta las sesiones; se retoman con el próximo mensaje.
  Future<void> connectOrStart({bool restart = false}) async {
    say('Conectando…');
    if (restart) {
      _drop();
    } else if (await connect()) {
      return;
    }
    say('Arrancando el puente en Termux…');
    await startBridge();
    // que start.sh llegue a matar el viejo: si no, conectamos con él justo antes de que muera
    if (restart) await Future<void>.delayed(const Duration(seconds: 3));
    for (var i = 0; i < 15 && !await connect(); i++) {
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    if (!connected) say('No arrancó: ¿instalaste el entorno? Mirá ~/.pixel-bridge.out en Termux.');
  }

  void _drop() {
    _socket?.destroy();
    _socket = null;
    busy.clear();
    notifyListeners();
  }

  void _send(Map<String, dynamic> m) => _socket?.writeln(jsonEncode(m));

  void _line(String l) {
    final Map<String, dynamic> m;
    try {
      m = jsonDecode(l) as Map<String, dynamic>;
    } on FormatException {
      return;
    }
    final id = m['id'] as String?;
    switch (m['op']) {
      case 'sessions':
        sessions = List<Map<String, dynamic>>.from(m['list'] as List);
      case 'event':
        final ev = m['event'] as Map<String, dynamic>;
        (events[id!] ??= []).add(ev);
        if (ev['type'] == 'result') busy.remove(id);
        if (ev['type'] == 'system' && ev['subtype'] == 'init') busy.add(id);
      case 'exit':
        busy.remove(id);
        refreshSessions();
      case 'error':
        busy.remove(id); // p. ej. no pudo lanzar claude
        status = m['message'] as String?;
    }
    notifyListeners();
  }

  void refreshSessions() => _send({'op': 'sessions'});

  /// Se suscribe una vez por conexión: el puente reenvía la historia y después lo nuevo.
  void open(String id, String cwd) {
    if (_open.containsKey(id)) return;
    _open[id] = cwd;
    events[id] = [];
    _send({'op': 'open', 'id': id, 'cwd': cwd});
  }

  void send(String id, String cwd, String text) {
    approvedTurn.remove(id);
    busy.add(id);
    // claude no repite los mensajes del usuario: lo mostramos ya (la historia lo trae al reconectar)
    (events[id] ??= []).add({
      'type': 'user',
      'message': {'role': 'user', 'content': text},
    });
    _send({'op': 'send', 'id': id, 'cwd': cwd, 'text': text});
    notifyListeners();
  }

  void stop(String id) => _send({'op': 'stop', 'id': id});

  void close(String id) => _send({'op': 'close', 'id': id});

  String? cwdOf(String? id) =>
      id == null ? null : _open[id] ?? sessions.where((s) => s['id'] == id).firstOrNull?['cwd'] as String?;
}

final bridge = Bridge();

/// Bloques de contenido de un evento user/assistant (vacío si el contenido es texto plano).
Iterable<Map> blocksOf(Map ev) {
  final c = (ev['message'] as Map?)?['content'];
  return c is List ? c.whereType<Map>() : const [];
}

// ─── Política de permisos ────────────────────────────────────────────────────

enum Ask { allow, askTurn, askEach }

/// Nuestras tools llegan a approve como `mcp__launcher__<nombre>`.
String bareTool(String tool) => tool.startsWith('mcp__launcher__') ? tool.substring(15) : tool;

const _free = {
  'Read', 'Glob', 'Grep', 'LS', 'WebFetch', 'WebSearch', 'TodoWrite', 'Task', 'NotebookRead', //
  'BashOutput', 'ExitPlanMode', 'apps', 'launch_app', 'tabs_get',
};
final _shellRead = RegExp(r'^\s*(settings\s+(get|list)|dumpsys|pm\s+(list|path)|getprop|cmd\s+package\s+list)\b');
final _chained = RegExp(r'[;&|>`\n]|\$\(');
// ponytail: heurística por texto; no ve `cd /etc && … > x`, `cp`, `tee` ni `sed -i` fuera del proyecto
final _danger = RegExp(
  r'(^|[^\w.-])(rm|mv|sudo|dd|adb)(?![\w.-])|git\s+push|git\s+reset\s+.*--hard'
  r'|(curl|wget)\b.*\|\s*(sudo\s+)?\w*sh\b|chmod\s+(-\w*R|--recursive)',
);
final _redirect = RegExp(r'>>?\s*([^\s;&|>]+)');

/// ¿[path] (absoluto o relativo a [cwd]) cae dentro de [cwd]? Sin cwd conocido, nada está adentro.
bool inside(String path, String cwd) {
  if (cwd.isEmpty || path.isEmpty || path.startsWith('~')) return false;
  final root = Uri.directory(cwd, windows: false);
  // Uri(path:) y no parse: un '?' o '#' en el nombre no corta el path
  return root.resolveUri(Uri(path: path)).path.startsWith(root.path);
}

/// Lectura libre; escribir en la carpeta y Bash sin peligro, una vez por turno; el resto, cada vez.
Ask decide(String tool, Map input, String cwd, {required bool turnApproved}) {
  final t = bareTool(tool);
  final low = turnApproved ? Ask.allow : Ask.askTurn;
  if (_free.contains(t)) return Ask.allow;
  switch (t) {
    case 'Edit' || 'Write' || 'MultiEdit' || 'NotebookEdit':
      return inside('${input['file_path'] ?? input['notebook_path'] ?? ''}', cwd) ? low : Ask.askEach;
    case 'Bash':
      final c = '${input['command'] ?? ''}';
      final out = _redirect.allMatches(c).any((m) => m[1] != '/dev/null' && !inside(m[1]!, cwd));
      return _danger.hasMatch(c) || out ? Ask.askEach : low;
    case 'android_shell':
      final c = '${input['cmd'] ?? ''}';
      return _shellRead.hasMatch(c) && !_chained.hasMatch(c) ? Ask.allow : Ask.askEach;
  }
  return Ask.askEach;
}

/// Qué tool, sobre qué y qué puede romper: el texto del diálogo de permiso.
String repercussions(String tool, Map input) {
  final t = bareTool(tool);
  final on = input['command'] ?? input['cmd'] ?? input['file_path'] ?? input['notebook_path'] ?? input['path'];
  final risk = switch (t) {
    'Edit' || 'Write' || 'MultiEdit' || 'NotebookEdit' =>
      'Cambia ese archivo. Fuera de la carpeta de la sesión puede tocar otros proyectos o tu configuración.',
    'Bash' => 'Corre en Debian: puede borrar o pisar archivos, instalar paquetes o subir cambios.',
    'android_shell' => 'Corre como shell de Android: puede cambiar ajustes, desinstalar o frenar apps.',
    'install_apk' => 'Instala o actualiza una app. Si es el launcher, se cierra y vuelve a abrir.',
    'tabs_set' => 'Reemplaza todas tus pestañas: las que no estén en la lista nueva se pierden.',
    _ => 'Tool sin política conocida: no sé qué puede hacer.',
  };
  return '$t${on == null ? '' : ': $on'}\n$risk';
}

// ─── Servidor MCP ────────────────────────────────────────────────────────────

Map<String, Object> _schema(Map<String, String> props) => {
  'type': 'object',
  'properties': {
    for (final MapEntry(:key, :value) in props.entries) key: {'type': value},
  },
  'required': props.keys.toList(),
};

final _tools = [
  {
    'name': 'approve',
    'description': 'Pide permiso al usuario en el launcher (es la de --permission-prompt-tool).',
    'inputSchema': _schema({'tool_name': 'string', 'input': 'object', 'tool_use_id': 'string'}),
  },
  {
    'name': 'android_shell',
    'description':
        'Corre un comando como usuario shell de Android vía Shizuku (settings, pm, cmd, dumpsys, am…). '
        'Devuelve code, out y err.',
    'inputSchema': _schema({'cmd': 'string'}),
  },
  {
    'name': 'install_apk',
    'description':
        'Instala un APK con pm install -r vía Shizuku. Responde antes de instalar (instalar el launcher '
        'lo cierra). La ruta tiene que estar en /sdcard: Shizuku no ve los archivos de Debian.',
    'inputSchema': _schema({'path': 'string'}),
  },
  {'name': 'apps', 'description': 'Apps instaladas, con cuántas veces se abrió cada una.', 'inputSchema': _schema({})},
  {
    'name': 'launch_app',
    'description': 'Abre una app por su package.',
    'inputSchema': _schema({'package': 'string'}),
  },
  {
    'name': 'tabs_get',
    'description': 'Pestañas del launcher (JSON: [{kind, name, ...config}]).',
    'inputSchema': _schema({}),
  },
  {
    'name': 'tabs_set',
    'description':
        'Reemplaza las pestañas del launcher; mismo formato que tabs_get. Tipos: ${tabKinds.keys.join(', ')}.',
    'inputSchema': _schema({'tabs': 'array'}),
  },
];

/// Escucha en 127.0.0.1:8766/mcp. JSON-RPC sin SSE; todo pedido lleva el token.
Future<void> startMcp() async {
  try {
    (await HttpServer.bind(InternetAddress.loopbackIPv4, 8766)).listen(_serve);
  } on SocketException {
    // el puerto ya está tomado (otra instancia): sin MCP
  }
}

Future<void> _serve(HttpRequest req) async {
  final res = req.response;
  try {
    if (req.uri.path != '/mcp') {
      res.statusCode = HttpStatus.notFound;
    } else if (req.headers.value('authorization') != 'Bearer ${await claudeToken}') {
      res.statusCode = HttpStatus.unauthorized;
    } else if (req.method != 'POST') {
      res.statusCode = HttpStatus.methodNotAllowed; // sin SSE
    } else {
      final msg = jsonDecode(await utf8.decodeStream(req)) as Map<String, dynamic>;
      final id = msg['id'];
      if (id == null) {
        res.statusCode = HttpStatus.accepted; // notificación
        return;
      }
      final params = (msg['params'] as Map?) ?? {};
      final Map<String, Object> reply = switch (msg['method']) {
        'initialize' => {
          'result': {
            'protocolVersion': params['protocolVersion'] ?? '2025-06-18',
            'capabilities': {'tools': {}},
            'serverInfo': {'name': 'launcher', 'version': '1'},
          },
        },
        'ping' => {'result': {}},
        'tools/list' => {
          'result': {'tools': _tools},
        },
        'tools/call' => {'result': await _call('${params['name']}', (params['arguments'] as Map?) ?? {}, req.uri)},
        _ => {
          'error': {'code': -32601, 'message': 'Método desconocido'},
        },
      };
      res.headers.contentType = ContentType.json;
      res.write(jsonEncode({'jsonrpc': '2.0', 'id': id, ...reply}));
    }
  } catch (_) {
    res.statusCode = HttpStatus.badRequest;
  } finally {
    await res.close();
  }
}

Future<Map<String, Object>> _call(String name, Map args, Uri from) async {
  String text;
  var error = false;
  try {
    text = switch (name) {
      'approve' => await _approve(args, from),
      'android_shell' => jsonEncode(await shizuku('${args['cmd']}')),
      'install_apk' => _install('${args['path']}'),
      'apps' => jsonEncode([
        for (final a in store.byUse) {'name': a.name, 'package': a.packageName, 'opens': store.uses(a.packageName)},
      ]),
      'launch_app' => await _launch('${args['package']}'),
      'tabs_get' => jsonEncode(tabStore.tabs),
      'tabs_set' => await _setTabs(args['tabs']),
      _ => throw 'Tool desconocida: $name',
    };
  } on PlatformException catch (e) {
    error = true;
    text = e.code == 'no-shizuku'
        ? 'Shizuku no está corriendo o no autorizó al launcher (pestaña TERMINAL → PERMISO SHIZUKU).'
        : e.message ?? e.code;
  } catch (e) {
    error = true;
    text = '$e';
  }
  return {
    'content': [
      {'type': 'text', 'text': text},
    ],
    'isError': error,
  };
}

/// Comando como usuario shell vía Shizuku: {code, out, err}.
Future<Map?> shizuku(String cmd) => native.invokeMethod<Map>('shizuku', {'cmd': cmd});

String _install(String path) {
  // primero responde: si el APK es el launcher, instalarlo lo mata
  Future.delayed(
    const Duration(seconds: 1),
    // desacoplado: Shizuku mata los procesos de una app cuando ella muere, y la instalación la mata
    () => shizuku(
      "setsid nohup pm install -r -d '${path.replaceAll("'", r"'\''")}' > /data/local/tmp/pixel-install.log 2>&1 &",
    ),
  ).catchError((_) => null);
  return 'Instalando $path en 1 s.';
}

Future<String> _launch(String pkg) async {
  if (!store.apps.any((a) => a.packageName == pkg)) throw 'No está instalada: $pkg';
  await store.launch(pkg);
  return 'Abierta.';
}

Future<String> _setTabs(Object? tabs) async {
  if (tabs is! List || tabs.any((t) => t is! Map || !tabKinds.containsKey(t['kind']) || t['name'] is! String)) {
    throw 'tabs: lista de {kind, name, ...}; kind es uno de ${tabKinds.keys.join(', ')}';
  }
  await tabStore.replace([for (final t in tabs) Map<String, dynamic>.from(t as Map)]);
  return 'Listo: ${tabs.length} pestañas.';
}

/// El pedido de permiso de Claude: según la política, deja pasar o pregunta con un diálogo pixel.
/// El puente pone la sesión y su carpeta en la URL del MCP (`/mcp?session=…&cwd=…`).
Future<String> _approve(Map args, Uri from) async {
  final tool = '${args['tool_name']}';
  final input = (args['input'] as Map?) ?? {};
  final id = from.queryParameters['session'];
  final cwd = from.queryParameters['cwd'] ?? bridge.cwdOf(id) ?? '';
  final ask = decide(tool, input, cwd, turnApproved: bridge.approvedTurn.contains(id));
  // modo AUTO de la pestaña que muestra esta sesión: todo permitido, sin preguntar
  final auto = tabStore.tabs.any((t) => t['session'] == id && t['auto'] == true);
  var ok = auto || ask == Ask.allow;
  final ctx = navigatorKey.currentContext;
  if (!ok && ctx != null) {
    ok =
        await showPixelDialog<bool>(
          ctx,
          ask == Ask.askTurn ? '¿Permitir? (vale por este turno)' : '¿Permitir?',
          (c) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(repercussions(tool, input), style: Px.text),
              const SizedBox(height: 8),
              PixelTile(
                autofocus: true,
                label: '${padLabel(PadButton.ok)} PERMITIR',
                onTap: () => Navigator.pop(c, true),
              ),
              const SizedBox(height: 4),
              PixelTile(label: '${padLabel(PadButton.back)} DENEGAR', onTap: () => Navigator.pop(c, false)),
            ],
          ),
        ) ==
        true;
    if (ok && ask == Ask.askTurn && id != null) bridge.approvedTurn.add(id);
  }
  return jsonEncode(
    ok ? {'behavior': 'allow', 'updatedInput': input} : {'behavior': 'deny', 'message': 'El usuario no lo permitió.'},
  );
}
