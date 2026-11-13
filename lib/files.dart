import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

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
    final apps = List<Map>.from(await native.invokeMethod<List>('appsFor', {'path': local}) ?? const [])
      ..sort((a, b) => '${a['label']}'.toLowerCase().compareTo('${b['label']}'.toLowerCase()));
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
    // un PlatformException trae todo el stack de Java: solo la primera línea del mensaje
    bridge.say(e is PlatformException ? (e.message ?? e.code).split('\n').first : '$e');
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

// ─── Tarjeta con vista previa ────────────────────────────────────────────────

/// Copias locales por archivo generado (clave: id del tool_use), para no traerlas de nuevo al scrollear.
final _local = <String, Future<String>>{};
final _thumbs = <String, Future<String?>>{};

const _previewable = {'html', 'imagen', 'pdf', 'video'};

Future<String> _fetch(String id, String path) => _local[id] ??= bridge.fetchFile(path)
  ..ignore()
  ..catchError((_) {
    _local.remove(id); // que un fallo (puente caído) se pueda reintentar
    return '';
  });

/// Miniatura PNG de un PDF o video (con Android); null si no se pudo.
Future<String?> _thumb(String id, String local) =>
    _thumbs[id] ??= native.invokeMethod<String>('thumb', {'path': local, 'out': '$local.png'});

/// Archivo que generó Claude: vista previa (cuando se puede) y abajo ABRIR CON. Tocar la vista previa
/// la agranda; ABRIR CON abre con la última app de su tipo (mantener o menú: elegir otra).
class FileCard extends StatelessWidget {
  const FileCard({super.key, required this.path, required this.id});

  final String path;
  final String id;

  @override
  Widget build(BuildContext context) {
    final kind = fileKind(path);
    final app = fileOpeners.of(kind);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_previewable.contains(kind))
          FutureBuilder<String>(
            future: _fetch(id, path),
            builder: (context, snap) {
              final local = snap.data;
              return GestureDetector(
                onTap: local == null || local.isEmpty ? null : () => _expand(context, local, kind),
                child: Container(
                  height: 150,
                  clipBehavior: Clip.hardEdge,
                  decoration: Px.box(),
                  child: switch (snap) {
                    AsyncSnapshot(hasError: true) => _msg('sin vista previa: ${snap.error}'),
                    _ when local == null => _msg('cargando…'),
                    _ when local.isEmpty => _msg('sin vista previa'),
                    _ => _Preview(local: local, kind: kind, id: id, thumb: true),
                  },
                ),
              );
            },
          ),
        if (_previewable.contains(kind)) const SizedBox(height: 4),
        PixelTile(
          maxLines: 2,
          label: '▣ ${baseName(path)}\nABRIR CON ${app == null ? '…' : app['label']!.toUpperCase()}',
          onTap: () => openGenerated(context, path),
          onLongPress: () => showFileMenu(context, path),
        ),
      ],
    );
  }

  Widget _msg(String t) => Center(
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Text(
        t,
        style: Px.text.copyWith(color: Px.dimText),
        textAlign: TextAlign.center,
      ),
    ),
  );

  /// Vista grande: interactiva (el html se puede usar), con ABRIR CON arriba.
  void _expand(BuildContext context, String local, String kind) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (ctx) => Scaffold(
        backgroundColor: Px.bg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    PixelTile(autofocus: true, label: '< VOLVER', onTap: () => Navigator.pop(ctx)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: PixelTile(
                        label: 'ABRIR CON…',
                        onTap: () => openGenerated(ctx, path),
                        onLongPress: () => showFileMenu(ctx, path),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Container(
                    clipBehavior: Clip.hardEdge,
                    decoration: Px.box(),
                    child: _Preview(local: local, kind: kind, id: id, thumb: false),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Contenido de la vista previa: [thumb] es la miniatura (sin interacción); si no, la vista grande.
class _Preview extends StatefulWidget {
  const _Preview({required this.local, required this.kind, required this.id, required this.thumb});

  final String local;
  final String kind;
  final String id;
  final bool thumb;

  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  WebViewController? web;

  @override
  void initState() {
    super.initState();
    if (widget.kind == 'html') {
      web = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.white)
        ..loadHtmlString(File(widget.local).readAsStringSync());
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.kind) {
      case 'html':
        final w = WebViewWidget(controller: web!);
        // miniatura: se ve la página pero no se toca (el toque es para agrandar)
        return widget.thumb ? IgnorePointer(child: w) : w;
      case 'imagen':
        return _image(FileImage(File(widget.local)));
      case 'pdf' || 'video':
        return FutureBuilder<String?>(
          future: _thumb(widget.id, widget.local),
          builder: (context, s) => s.data == null
              ? Center(
                  child: Text(
                    s.connectionState == ConnectionState.done ? 'sin vista previa' : 'cargando…',
                    style: Px.text.copyWith(color: Px.dimText),
                  ),
                )
              : _image(FileImage(File(s.data!))),
        );
      default:
        return const SizedBox.shrink(); // los demás tipos no tienen vista previa
    }
  }

  Widget _image(ImageProvider p) => widget.thumb
      ? Image(image: p, fit: BoxFit.cover, alignment: Alignment.topCenter, width: double.infinity)
      : InteractiveViewer(
          maxScale: 6,
          child: Center(child: Image(image: p)),
        );
}
