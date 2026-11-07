import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'apps.dart';
import 'pad.dart';
import 'pages.dart';
import 'trinkets.dart';
import 'ui.dart';

typedef Config = Map<String, dynamic>;

/// Una utilidad que se puede poner en una pestaña.
class Utility {
  const Utility(this.label, {required this.create, required this.build, this.actions, this.remove});

  final String label;

  /// Pide lo que haga falta y devuelve la config inicial (null = cancelar).
  final Future<Config?> Function(BuildContext context) create;

  /// Dibuja la utilidad; su estado vive en la config y se guarda con `save`.
  final Widget Function(Config cfg, VoidCallback save) build;

  /// Opciones propias que se suman al menú del encabezado.
  final List<(String, VoidCallback)> Function(BuildContext context, Config cfg, VoidCallback save)? actions;

  /// Limpieza al quitarla o al borrar su pestaña.
  final void Function(Config cfg)? remove;
}

/// Catálogo de utilidades. Agregá una nueva acá.
final utilities = <String, Utility>{
  'clock': Utility(
    'Reloj',
    create: (_) async => {},
    build: (_, _) => const FittedBox(child: ClockTrinket()),
  ),
  'stopwatch': Utility(
    'Cronómetro',
    create: (_) async => {'acc': 0, 'start': null},
    build: (cfg, save) => StopwatchUtil(cfg, save),
  ),
  'countup': Utility(
    'Cuenta arriba',
    create: (_) async => {'since': DateTime.now().millisecondsSinceEpoch},
    build: (cfg, save) => CountUpUtil(cfg, save),
  ),
  'web': Utility(
    'Web',
    create: (context) async {
      final url = await _askUrl(context);
      return url == null ? null : {'url': url};
    },
    build: (cfg, _) => WebUtil(cfg),
    actions: (context, cfg, save) => [
      ('Recargar', () => _webs[cfg]?.reload()),
      (
        'Cambiar dirección',
        () async {
          final url = await _askUrl(context, cfg['url'] as String);
          if (url == null) return;
          cfg['url'] = url;
          save();
          _webs[cfg]?.loadRequest(Uri.parse(url));
        },
      ),
      ('Abrir en navegador', () => openInBrowser(cfg['url'] as String)),
    ],
  ),
  'photos': Utility(
    'Fotos',
    create: (_) async {
      final photos = await pickPhotos();
      return photos.isEmpty ? null : {'photos': photos, 'i': 0};
    },
    build: (cfg, _) => PhotosUtil(cfg),
    actions: (context, cfg, save) {
      final photos = cfg['photos'] as List;
      // la que se ve al abrir el menú: mientras está abierto puede pasar a la siguiente
      final shown = photos.isEmpty ? null : photos[PhotosUtil.current(cfg)] as Map;
      void drop() {
        photos.remove(shown);
        File(shown!['path'] as String).delete().ignore(); // la copia del launcher, no la original
        save();
      }

      return [
        if (photos.length > 1)
          (
            'Siguiente foto',
            () {
              cfg['i'] = (cfg['i'] as int) + 1;
              save();
            },
          ),
        (
          'Agregar fotos',
          () async {
            photos.addAll(await pickPhotos());
            save();
          },
        ),
        if (shown != null) ('Quitar del cuadro', drop),
        if (shown != null)
          (
            'Borrar del teléfono',
            () => showPixelMenu(context, '¿Borrar del teléfono? No se puede deshacer', [
              ('Cancelar', () {}),
              (
                'Sí, borrar',
                () async {
                  final ok = await native.invokeMethod<bool>('deleteImage', {'uri': shown['uri']}) ?? false;
                  ok ? drop() : InstalledApps.toast('No se pudo borrar', false);
                },
              ),
            ]),
          ),
        (
          'Pixelado: ${PhotosUtil.pixel(cfg) ? 'sí' : 'no'}',
          () {
            cfg['pixel'] = !PhotosUtil.pixel(cfg);
            save();
          },
        ),
      ];
    },
  ),
  'apps': Utility(
    'Apps',
    create: (context) async {
      final apps = await pickApps(context);
      return apps == null || apps.isEmpty ? null : {'apps': apps};
    },
    build: (cfg, save) => AppsUtil(cfg, save),
  ),
  'widget': Utility(
    'Widget',
    create: (_) async {
      final id = await native.invokeMethod<int>('pickWidget');
      return id == null ? null : {'id': id};
    },
    build: (cfg, _) => AndroidView(
      viewType: 'pixel_launcher/widget',
      creationParams: cfg['id'],
      creationParamsCodec: const StandardMessageCodec(),
      // como la web: los arrastres verticales scrollean el widget, los horizontales cambian de pestaña
      gestureRecognizers: {Factory<OneSequenceGestureRecognizer>(VerticalDragGestureRecognizer.new)},
    ),
    remove: (cfg) => native.invokeMethod('deleteWidget', {'id': cfg['id']}),
  ),
};

Future<String?> _askUrl(BuildContext context, [String initial = '']) async {
  final url = (await askText(context, 'Dirección web', hint: 'ejemplo.com', initial: initial))?.trim();
  if (url == null || url.isEmpty) return null;
  return url.contains('://') ? url : 'https://$url';
}

/// Abre la URL en el navegador elegido en SYS, o en el del sistema si no hay o ya no está instalado.
Future<void> openInBrowser(String url) async {
  try {
    await AndroidIntent(action: 'action_view', data: url, package: store.browser).launch();
  } catch (_) {
    await AndroidIntent(action: 'action_view', data: url).launch();
  }
}

int _now() => DateTime.now().millisecondsSinceEpoch;

/// 3d 04:05:06 (los días solo si hay), con décimas opcionales: 04:05:06.7
String fmt(Duration d, {bool tenths = false}) =>
    '${d.inDays > 0 ? '${d.inDays}d ' : ''}'
    '${two(d.inHours % 24)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}'
    '${tenths ? '.${d.inMilliseconds % 1000 ~/ 100}' : ''}';

final _fastTick = Stream<void>.periodic(const Duration(milliseconds: 100)).asBroadcastStream();

/// Número grande que ocupa todo el lugar, con botones abajo.
Widget _display(Stream<void> ticker, String Function() text, List<Widget> buttons) => Column(
  children: [
    Expanded(
      child: FittedBox(
        child: StreamBuilder(
          stream: ticker,
          builder: (_, _) => Text(text(), style: Px.big),
        ),
      ),
    ),
    Row(
      children: [
        for (final (i, b) in buttons.indexed) ...[if (i > 0) const SizedBox(width: 8), Expanded(child: b)],
      ],
    ),
  ],
);

/// Cronómetro. Guarda el acumulado y desde cuándo corre, así sigue contando con el launcher cerrado.
class StopwatchUtil extends StatelessWidget {
  const StopwatchUtil(this.cfg, this.save, {super.key});

  final Config cfg;
  final VoidCallback save;

  bool get running => cfg['start'] != null;
  int get elapsed => (cfg['acc'] as int) + (running ? _now() - (cfg['start'] as int) : 0);

  @override
  Widget build(BuildContext context) => _display(_fastTick, () => fmt(Duration(milliseconds: elapsed), tenths: true), [
    PixelTile(
      label: running ? 'PAUSA' : 'INICIAR',
      onTap: () {
        cfg
          ..['acc'] = elapsed
          ..['start'] = running ? null : _now();
        save();
      },
    ),
    PixelTile(
      label: 'RESET',
      onTap: () {
        cfg
          ..['acc'] = 0
          ..['start'] = running ? _now() : null;
        save();
      },
    ),
  ]);
}

/// Tiempo transcurrido desde que se creó (o se reinició).
class CountUpUtil extends StatelessWidget {
  const CountUpUtil(this.cfg, this.save, {super.key});

  final Config cfg;
  final VoidCallback save;

  @override
  Widget build(BuildContext context) =>
      _display(tick, () => fmt(Duration(milliseconds: _now() - (cfg['since'] as int))), [
        PixelTile(
          label: 'REINICIAR',
          onTap: () {
            cfg['since'] = _now();
            save();
          },
        ),
      ]);
}

/// La web que tiene el foco: se lleva todos los gestos (también los horizontales) y la shell
/// deja de cambiar de pestaña con swipe hasta que se toca "atrás".
final webFocus = ValueNotifier<Object?>(null);

/// Página web. Sin foco, los arrastres verticales la scrollean y los horizontales cambian de pestaña.
/// Al tocarla toma el foco.
class WebUtil extends StatefulWidget {
  const WebUtil(this.cfg, {super.key});

  final Config cfg;

  @override
  State<WebUtil> createState() => _WebUtilState();
}

/// El navegador de cada web abierta, por su config: así su menú puede recargarla.
final _webs = Expando<WebViewController>();

class _WebUtilState extends State<WebUtil> {
  late final controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..loadRequest(Uri.parse(widget.cfg['url'] as String));

  @override
  void initState() {
    super.initState();
    _webs[widget.cfg] = controller;
  }

  @override
  void dispose() {
    // al final del frame: durante el dispose el árbol está bloqueado
    if (webFocus.value == this) WidgetsBinding.instance.addPostFrameCallback((_) => webFocus.value = null);
    super.dispose();
  }

  bool selected = false; // la eligió el mando, todavía sin entrar

  /// Con el mando: confirmar entra (como tocarla), las flechas scrollean y volver suelta.
  KeyEventResult _key(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (webFocus.value != this) {
      if (!isOk(k)) return KeyEventResult.ignored;
      webFocus.value = this;
      return KeyEventResult.handled;
    }
    final step = (context.size?.height ?? 300) * MediaQuery.devicePixelRatioOf(context) * 0.8 ~/ 1;
    final (dx, dy) = switch (k) {
      LogicalKeyboardKey.arrowUp => (0, -step),
      LogicalKeyboardKey.arrowDown => (0, step),
      LogicalKeyboardKey.arrowLeft => (-step, 0),
      LogicalKeyboardKey.arrowRight => (step, 0),
      _ => (0, 0),
    };
    if (dx == 0 && dy == 0) return KeyEventResult.ignored;
    controller.scrollBy(dx, dy);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: webFocus,
    builder: (context, focused, _) {
      final mine = focused == this;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Focus(
              onFocusChange: (f) => setState(() => selected = f),
              onKeyEvent: _key,
              child: Container(
                foregroundDecoration: mine || selected
                    ? BoxDecoration(
                        border: Border.all(color: mine ? Px.accent : Px.fg, width: Px.unit * 2),
                      )
                    : null,
                child: Listener(
                  onPointerDown: (_) => webFocus.value = this,
                  child: WebViewWidget(
                    controller: controller,
                    gestureRecognizers: {
                      mine
                          ? Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new)
                          : Factory<OneSequenceGestureRecognizer>(VerticalDragGestureRecognizer.new),
                    },
                  ),
                ),
              ),
            ),
          ),
          if (mine)
            Text('${padLabel(PadButton.back)} o ATRÁS para soltar', style: Px.text.copyWith(color: Px.accent))
          else if (selected)
            Text('${padLabel(PadButton.ok)} para entrar', style: Px.text),
        ],
      );
    },
  );
}

/// Abre el selector de imágenes del sistema; devuelve [{path, uri}] (vacío = cancelar): path es una
/// copia propia para mostrarla, uri la original del teléfono.
// ponytail: las copias de una utilidad borrada quedan en disco; limpiar huérfanas si pesa.
Future<List<Map>> pickPhotos() async => [
  for (final p in await native.invokeMethod<List>('pickImages') ?? []) Map<String, dynamic>.from(p as Map),
];

/// Cuadro de fotos: pasa a la siguiente cada [every] segundos. La foto que toca sale de la hora,
/// así no hace falta un State; 'i' suma los "siguiente" manuales.
class PhotosUtil extends StatelessWidget {
  const PhotosUtil(this.cfg, {super.key});

  final Config cfg;

  static const every = 15;

  static bool pixel(Config cfg) => cfg['pixel'] != false;

  static int current(Config cfg) => ((cfg['i'] as int) + _now() ~/ 1000 ~/ every) % (cfg['photos'] as List).length;

  @override
  Widget build(BuildContext context) => StreamBuilder(
    stream: tick,
    builder: (context, _) {
      final photos = cfg['photos'] as List;
      if (photos.isEmpty) {
        return Center(
          child: Text('SIN FOTOS', style: Px.text.copyWith(color: Px.dimText)),
        );
      }
      return LayoutBuilder(
        builder: (context, box) => Image.file(
          File((photos[current(cfg)] as Map)['path'] as String),
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.cover,
          // decodificada chica: pixelada a propósito, o al ancho del cuadro para no gastar memoria
          cacheWidth: pixel(cfg) ? Px.photoRes : (box.maxWidth * MediaQuery.devicePixelRatioOf(context)).round(),
          filterQuality: pixel(cfg) ? FilterQuality.none : FilterQuality.medium,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => Center(
            child: Text('NO SE PUDO ABRIR', style: Px.text.copyWith(color: Px.dimText)),
          ),
        ),
      );
    },
  );
}

/// Accesos rápidos a las apps elegidas. El último tile reabre el selector para sumar o sacar apps.
class AppsUtil extends StatelessWidget {
  const AppsUtil(this.cfg, this.save, {super.key});

  final Config cfg;
  final VoidCallback save;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final packages = List<String>.from(cfg['apps'] as List);
      final apps = [for (final p in packages) ...store.apps.where((a) => a.packageName == p)];
      return GridView.extent(
        maxCrossAxisExtent: 110,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.9,
        padding: const EdgeInsets.only(right: Px.unit * 2, bottom: Px.unit * 2),
        children: [
          for (final a in apps) appTile(context, a, vertical: true),
          PixelTile(
            vertical: true,
            label: '+ APPS',
            onTap: () async {
              final picked = await pickApps(context, packages);
              if (picked == null || picked.isEmpty) return;
              cfg['apps'] = picked;
              save();
            },
          ),
        ],
      );
    },
  );
}

/// Lista de apps para marcar, con [initial] ya marcadas; devuelve los packageNames elegidos (null = cancelar).
Future<List<String>?> pickApps(BuildContext context, [List<String> initial = const []]) {
  final picked = [...initial];
  return showPixelDialog<List<String>>(
    context,
    'Elegí apps',
    (ctx) => StatefulBuilder(
      builder: (ctx, setState) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(ctx).height * 0.5,
            child: ListView(
              children: [
                for (final a in store.apps)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: PixelTile(
                      label: '${picked.contains(a.packageName) ? '[x]' : '[ ]'} ${a.name}',
                      leading: PixelIcon(a.icon),
                      onTap: () => setState(() {
                        if (!picked.remove(a.packageName)) picked.add(a.packageName);
                      }),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          PixelTile(autofocus: true, label: 'LISTO', onTap: () => Navigator.pop(ctx, picked)),
        ],
      ),
    ),
  );
}
