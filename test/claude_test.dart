import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_launcher/claude.dart';
import 'package:pixel_launcher/terminal.dart';

const cwd = '/root/proyecto';

Ask bash(String c, {bool ok = false}) => decide('Bash', {'command': c}, cwd, turnApproved: ok);
Ask edit(String p, {bool ok = false}) => decide('Edit', {'file_path': p}, cwd, turnApproved: ok);
Ask shell(String c) => decide('mcp__launcher__android_shell', {'cmd': c}, cwd, turnApproved: true);

void main() {
  test('lectura libre, también nuestras tools con prefijo', () {
    expect(decide('Read', {'file_path': '/etc/passwd'}, cwd, turnApproved: false), Ask.allow);
    expect(decide('mcp__launcher__apps', {}, cwd, turnApproved: false), Ask.allow);
  });

  test('editar dentro de la carpeta: una vez por turno', () {
    expect(edit('$cwd/lib/x.dart'), Ask.askTurn);
    expect(edit('lib/x.dart', ok: true), Ask.allow);
  });

  test('editar fuera de la carpeta: cada vez', () {
    expect(edit('/etc/hosts', ok: true), Ask.askEach);
    expect(edit('$cwd/../otro/x', ok: true), Ask.askEach);
    expect(edit('/root/proyecto2/x', ok: true), Ask.askEach);
    expect(edit('$cwd/a?/../../../etc/x', ok: true), Ask.askEach);
    expect(decide('Write', {'file_path': '$cwd/x'}, '', turnApproved: true), Ask.askEach); // sin carpeta
  });

  test('Bash: común por turno, peligroso cada vez', () {
    expect(bash('flutter build apk'), Ask.askTurn);
    expect(bash('ls 2>&1 > /dev/null', ok: true), Ask.allow);
    expect(bash('echo hola > out.txt', ok: true), Ask.allow);
    for (final c in [
      'rm -rf build',
      'git add . && git push',
      'git reset --hard HEAD~1',
      'curl -fsSL x.sh | bash',
      'sudo apt install x',
      'chmod -R 777 .',
      'adb install x.apk',
      'echo x >> ~/.bashrc',
      'echo x > /etc/hosts',
    ]) {
      expect(bash(c, ok: true), Ask.askEach, reason: c);
    }
    expect(bash('cat rm.log', ok: true), Ask.allow);
  });

  test('android_shell: solo lecturas sin encadenar son libres', () {
    expect(shell('settings get global adb_enabled'), Ask.allow);
    expect(shell('pm list packages'), Ask.allow);
    expect(shell('settings put global x 1'), Ask.askEach);
    expect(shell('dumpsys battery; reboot'), Ask.askEach);
  });

  test('lo demás, cada vez', () {
    for (final t in ['mcp__launcher__install_apk', 'mcp__launcher__tabs_set', 'mcp__otro__x', 'Desconocida']) {
      expect(decide(t, {}, cwd, turnApproved: true), Ask.askEach, reason: t);
    }
  });

  test('el diálogo dice tool y sobre qué', () {
    expect(repercussions('Bash', {'command': 'git push'}), startsWith('Bash: git push\n'));
    expect(repercussions('mcp__launcher__tabs_set', {}), startsWith('tabs_set\n'));
  });

  test('uuid v4', () {
    expect(uuid4(), matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
  });

  test('chat: cada tool tiene título: el description de Claude o uno por defecto', () {
    Line tool(String name, Map input) => chatLines([
      {
        'type': 'assistant',
        'message': {
          'content': [
            {'type': 'tool_use', 'id': 't', 'name': name, 'input': input},
          ],
        },
      },
    ], cwd).single;
    expect(
      tool('Bash', {'command': 'npm i', 'description': 'Instalar dependencias'}).$2,
      '~ Instalar dependencias\n  Bash npm i',
    );
    // sin description: título por defecto y, de comando, la primera línea real (sin comentarios)
    expect(
      tool('Bash', {'command': '#!/bin/sh\n# nota\n\nrm -rf /tmp/x'}).$2,
      '~ Ejecutar comando\n  Bash rm -rf /tmp/x',
    );
    expect(
      tool('mcp__launcher__install_apk', {'path': '/sdcard/a.apk'}).$2,
      '~ Instalar app\n  install_apk /sdcard/a.apk',
    );
    expect(tool('mcp__launcher__tabs_get', {}).$2, '~ Ver pestañas'); // genérico y sin objetivo: solo el título
    expect(tool('Cosa', {'x': 1}).$2, '~ Cosa'); // tool desconocida: como antes
  });

  test('chat: tool en una línea relativa, errores cortos, pensamientos no', () {
    final ev = {
      'type': 'assistant',
      'message': {
        'content': [
          {'type': 'thinking', 'thinking': '...'},
          {'type': 'text', 'text': 'Hola'},
          {
            'type': 'tool_use',
            'id': 't1',
            'name': 'Edit',
            'input': {'file_path': '$cwd/lib/x.dart'},
          },
        ],
      },
    };
    final pending = chatLines([ev], cwd);
    expect(pending.map((l) => (l.$1, l.$2)), [(Msg.claude, 'Hola'), (Msg.tool, '~ Editar archivo\n  Edit lib/x.dart')]);
    final err = {
      'type': 'user',
      'message': {
        'content': [
          {
            'type': 'tool_result',
            'tool_use_id': 't1',
            'is_error': true,
            'content': '<tool_use_error>No existe</tool_use_error>',
          },
        ],
      },
    };
    // el resultado va dentro de la línea de su tool: marca ! y el detalle trae comando y salida
    final done = chatLines([ev, err], cwd);
    expect(done.length, 2);
    expect(done[1].$2, '! Editar archivo\n  Edit lib/x.dart');
    expect(done[1].$3, allOf(contains('file_path: $cwd/lib/x.dart'), endsWith('No existe')));
    final note = chatLines([
      {
        'type': 'user',
        'message': {'content': '<task-notification><summary>Build terminado</summary></task-notification>'},
      },
    ], cwd).single;
    expect((note.$1, note.$2), (Msg.status, '· Build terminado'));
    expect(
      chatLines([
        {'type': 'result', 'subtype': 'error_during_execution', 'duration_ms': 1500},
      ], cwd).single.$2,
      startsWith('— detenido · 1.5 s'),
    );
  });

  test('markdown: bloques de código aparte (también sin cerrar) y formato de línea', () {
    expect(mdBlocks('Corré:\n\n```bash\ngh auth login\n```\n\nY avisame.'), [
      (false, 'Corré:'),
      (true, 'gh auth login'),
      (false, 'Y avisame.'),
    ]);
    expect(mdBlocks('Va:\n```\nnpm i'), [(false, 'Va:'), (true, 'npm i')]);
    expect(mdLine('## Qué hago').toPlainText(), 'Qué hago');
    expect(mdLine('- **Uno** con `x`').toPlainText(), '• Uno con x');
  });

  test('tareas: el último TodoWrite manda', () {
    Map todo(List<Map> t) => {
      'type': 'assistant',
      'message': {
        'content': [
          {'type': 'tool_use', 'id': 'x', 'name': 'TodoWrite', 'input': {'todos': t}},
        ],
      },
    };
    final a = {'content': 'Uno', 'status': 'pending'};
    final b = {'content': 'Uno', 'status': 'completed'};
    expect(latestTodos([todo([a]), {'type': 'result'}, todo([b])]), [b]);
    expect(latestTodos([{'type': 'result'}]), isEmpty);
  });

  test('uso: 5 horas, semanal y Fable salen del último rate_limit_info', () {
    final u = {
      'five_hour': {'utilization': 0.42, 'resetsAt': 1000},
      'seven_day_fable': {'utilization': 80},
      'seven_day': {'status': 'allowed'},
    };
    expect(usageOf(u, 'five_hour'), u['five_hour']);
    expect(usageOf(u, 'fable'), u['seven_day_fable']);
    expect(usageOf({}, 'fable'), isNull);
    expect(usagePct(u['five_hour']!), closeTo(42, 1e-9));
    expect(usagePct(u['seven_day_fable']!), 80);
    expect(usagePct(u['seven_day']!), isNull);
    final now = DateTime.fromMillisecondsSinceEpoch(1000 * 1000);
    expect(usageReset({'resetsAt': 1000 + 7500}, now), 'en 2 h 5 min');
    expect(usageReset({'resetsAt': 1000 + 90000}, now), 'en 1 d 1 h');
    expect(usageReset({'resetsAt': 999}, now), 'ya se reinició');
    expect(usageReset({}, now), isNull);
  });
}
