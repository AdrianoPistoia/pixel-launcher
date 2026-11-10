import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:installed_apps/installed_apps.dart';

import 'apps.dart';
import 'pad.dart';
import 'pages.dart';
import 'tabs.dart';
import 'trinkets.dart';
import 'ui.dart';
import 'utilities.dart';

// Las cuatro vistas que salieron de las propuestas de UX: Terminal, Bitácora, Consola y Órbita.

Widget _label(String text) => Text(
  text,
  style: Px.text.copyWith(fontSize: Px.sz(18), color: Px.dimText, letterSpacing: 1),
);

/// Inicial para agrupar y filtrar: sin tildes, '#' si no es letra.
String initialOf(String name) {
  const plain = {'Á': 'A', 'À': 'A', 'É': 'E', 'Í': 'I', 'Ó': 'O', 'Ú': 'U', 'Ü': 'U', 'Ñ': 'N'};
  if (name.isEmpty) return '#';
  final c = name[0].toUpperCase();
  final p = plain[c] ?? c;
  return RegExp('[A-Z]').hasMatch(p) ? p : '#';
}

// ─── Terminal ────────────────────────────────────────────────────────────────

/// Vista "buscar" de la pestaña TERMINAL: apps sugeridas para esta hora, las fijadas y una línea de comandos.
/// Escribir filtra apps (Enter abre la primera); `web <dirección>` abre una web.
class TerminalPage extends StatefulWidget {
  const TerminalPage({super.key});

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> with TickerProviderStateMixin {
  final input = TextEditingController();
  // booteo al entrar: como PageView destruye la página al salir, se repite en cada visita
  late final boot = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  // barra de carga de Enter: 10 saltos antes de abrir
  late final bar = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
  AppInfo? loading;

  String get query => input.text.trim().toLowerCase();
  List<AppInfo> get matches => store.apps.where((a) => a.name.toLowerCase().contains(query)).toList();
  bool get still => MediaQuery.disableAnimationsOf(context);

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_skip);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (boot.status == AnimationStatus.dismissed) still ? boot.value = 1 : boot.forward();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_skip);
    boot.dispose();
    bar.dispose();
    input.dispose();
    super.dispose();
  }

  /// Cualquier tecla o toque saltea el booteo. No se come la tecla.
  bool _skip([Object? _]) {
    if (boot.isAnimating) boot.value = 1;
    return false;
  }

  void run(String cmd) {
    final c = cmd.trim();
    if (c.toLowerCase().startsWith('web ')) {
      final url = c.substring(4).trim();
      if (url.isNotEmpty) openInBrowser(url.contains('://') ? url : 'https://$url');
    } else if (c.isNotEmpty && matches.isNotEmpty && loading == null) {
      final app = matches.first;
      if (still) {
        store.launch(app.packageName);
      } else {
        loading = app;
        bar.forward(from: 0).then((_) {
          store.launch(app.packageName);
          if (mounted) setState(() => loading = null);
        });
      }
    }
    input.clear();
    setState(() {});
  }

  /// Líneas del booteo con datos reales; cada una se tipea en su tramo del primer 60 %.
  Widget _bootLog() {
    final opens = store.usage.values.fold<int>(0, (a, u) => a + u.fold<int>(0, (b, n) => b + n));
    final lines = [
      'pixel-launcher',
      'apps instaladas ..... ${store.apps.length}',
      'aperturas ........... $opens',
      'sugerencias ......... ${DateTime.now().hour} h',
    ];
    return AnimatedBuilder(
      animation: boot,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, l) in lines.indexed)
            Builder(
              builder: (context) {
                final f = ((boot.value - i * 0.15) / 0.15).clamp(0.0, 1.0);
                return Text.rich(
                  TextSpan(
                    text: l.substring(0, (l.length * f).floor()),
                    children: [
                      if (f == 1)
                        TextSpan(
                          text: ' OK',
                          style: TextStyle(color: Px.accent),
                        ),
                    ],
                  ),
                  style: Px.text.copyWith(fontSize: Px.sz(17), color: Px.dimText),
                  maxLines: 1,
                );
              },
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final suggested = store.suggestions(DateTime.now().hour);
      return Listener(
        onPointerDown: _skip,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _bootLog(),
            const SizedBox(height: 8),
            _label('A ESTA HORA'),
            const SizedBox(height: 8),
            if (suggested.isEmpty)
              Text('todavía sin datos: abrí apps y van a aparecer acá', style: Px.text.copyWith(color: Px.dimText))
            else
              AnimatedBuilder(
                animation: boot,
                // en cascada al final del booteo, 60 ms entre una y otra
                builder: (context, _) => Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (i, a) in suggested.indexed)
                      Opacity(
                        opacity: boot.value >= 0.6 + i * 0.067 ? 1 : 0,
                        child: PixelTile(
                          label: a.name,
                          leading: PixelIcon(a.icon),
                          onTap: () => store.launch(a.packageName),
                          onLongPress: () => showAppMenu(context, a),
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Expanded(
              child: query.isEmpty
                  ? _pinned(context)
                  : ListView.separated(
                      itemCount: matches.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 4),
                      itemBuilder: (context, i) => appTile(context, matches[i], match: query),
                    ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: input,
              style: Px.text,
              cursorWidth: 10, // cursor de bloque; el TextField ya lo hace titilar
              decoration: Px.input('buscar o comando').copyWith(
                prefixText: '> ',
                prefixStyle: Px.text.copyWith(color: Px.accent),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: run,
            ),
            const SizedBox(height: 6),
            if (loading != null)
              AnimatedBuilder(
                animation: bar,
                builder: (context, _) {
                  final n = (bar.value * 10).floor();
                  return Text(
                    '[${'#' * n}${'.' * (10 - n)}] ${loading!.name}',
                    style: Px.text.copyWith(fontSize: Px.sz(17), color: Px.accent),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  );
                },
              )
            else
              Text(
                'Enter abre la primera · web <dirección> abre una web',
                style: Px.text.copyWith(fontSize: Px.sz(17), color: Px.dimText),
              ),
          ],
        ),
      );
    },
  );

  Widget _pinned(BuildContext context) {
    final apps = store.pinnedApps;
    if (apps.isEmpty) {
      return Align(
        alignment: Alignment.bottomLeft,
        child: Text('fijá apps manteniéndolas apretadas', style: Px.text.copyWith(color: Px.dimText)),
      );
    }
    final landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label('FIJADAS'),
        const SizedBox(height: 8),
        Flexible(
          child: GridView.count(
            crossAxisCount: landscape ? 8 : 4,
            shrinkWrap: true,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.85,
            padding: const EdgeInsets.only(right: Px.unit * 2, bottom: Px.unit * 2),
            children: [for (final a in apps) appTile(context, a, vertical: true)],
          ),
        ),
      ],
    );
  }
}

// ─── Bitácora ────────────────────────────────────────────────────────────────

TextStyle _sans(double size, {double weight = 400, Color? color}) => TextStyle(
  fontFamily: 'SpaceGrotesk',
  fontSize: size,
  color: color ?? Px.fg,
  fontVariations: [FontVariation('wght', weight)],
);

TextStyle _mono(double size, {Color? color}) =>
    TextStyle(fontFamily: 'PlexMono', fontSize: size, color: color ?? Px.dimText, letterSpacing: 1);

String greeting(int hour) => hour < 6
    ? 'Buenas noches'
    : hour < 13
    ? 'Buen día'
    : hour < 20
    ? 'Buenas tardes'
    : 'Buenas noches';

/// Bitácora: saludo, lo que está corriendo ahora (cronómetros y cuentas de tus pestañas)
/// y todas las apps en lista de texto agrupada por letra, con índice A–Z para saltar.
class BitacoraPage extends StatefulWidget {
  const BitacoraPage({super.key});

  @override
  State<BitacoraPage> createState() => _BitacoraPageState();
}

class _BitacoraPageState extends State<BitacoraPage> {
  static const headerH = 28.0;
  static const rowH = 44.0;

  final scroll = ScrollController();
  String query = '';
  String? letter; // última letra elegida en el índice

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([store, tabStore]),
    builder: (context, _) {
      final landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
      final head = [
        Text(greeting(DateTime.now().hour), style: _sans(landscape ? 28 : 36, weight: 500)),
        const SizedBox(height: 12),
      ];
      final list = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _list()),
          const SizedBox(height: 8),
          TextField(
            style: _mono(14, color: Px.fg),
            decoration: InputDecoration(
              hintText: 'Buscar apps',
              hintStyle: _mono(14),
              isDense: true,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: BorderSide(color: Px.dim, width: Px.unit),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: BorderSide(color: Px.fg, width: Px.unit),
              ),
            ),
            onChanged: (v) => setState(() => query = v),
          ),
        ],
      );
      if (landscape) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 300,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ...head,
                  Expanded(child: _now(column: true)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: list),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...head,
          SizedBox(height: 150, child: _now(column: false)),
          const SizedBox(height: 12),
          Expanded(child: list),
        ],
      );
    },
  );

  /// Hasta 2 utilidades corriendo en tus pestañas: cronómetros en marcha y cuentas arriba.
  Widget _now({required bool column}) {
    final running = [
      for (final t in tabStore.tabs)
        if (t['kind'] == 'custom')
          for (final w in (t['widgets'] as List).cast<Config>())
            if ((w['type'] == 'stopwatch' && w['start'] != null) || w['type'] == 'countup') w,
    ].take(2).toList();
    if (running.isEmpty) {
      return Text('nada corriendo · sumá un cronómetro desde +', style: _mono(12));
    }
    final cards = [
      for (final w in running)
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Px.bg,
              border: Border.fromBorderSide(BorderSide(color: Px.dim, width: Px.unit)),
              boxShadow: [BoxShadow(color: Px.shadow, offset: Offset(3, 3))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(utilities[w['type']]!.label.toUpperCase(), style: _mono(11)),
                const SizedBox(height: 6),
                Expanded(child: utilities[w['type']]!.build(w, tabStore.save)),
              ],
            ),
          ),
        ),
    ];
    final spaced = [
      for (final (i, c) in cards.indexed) ...[if (i > 0) const SizedBox(width: 8, height: 8), c],
    ];
    return column
        ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced)
        : Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced);
  }

  Widget _list() {
    final q = query.toLowerCase();
    final apps = store.apps.where((a) => a.name.toLowerCase().contains(q)).toList()
      ..sort((a, b) {
        final c = initialOf(a.name).compareTo(initialOf(b.name));
        return c != 0 ? c : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    // filas (String = encabezado de letra, AppInfo = app) y desde qué alto arranca cada letra
    final rows = <Object>[];
    final offsets = <String, double>{};
    var y = 0.0;
    for (final a in apps) {
      final l = initialOf(a.name);
      if (!offsets.containsKey(l)) {
        offsets[l] = y;
        rows.add(l);
        y += headerH;
      }
      rows.add(a);
      y += rowH;
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView.builder(
            controller: scroll,
            itemCount: rows.length,
            itemBuilder: (context, i) {
              final r = rows[i];
              return r is String
                  ? SizedBox(
                      height: headerH,
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: Text(r, style: _mono(11, color: Px.accent)),
                      ),
                    )
                  : _AppRow(r as AppInfo, height: rowH);
            },
          ),
        ),
        _Scrubber(
          present: offsets.keys.toSet(),
          selected: letter,
          onPick: (l) {
            final o = offsets[l];
            if (o == null || !scroll.hasClients) return;
            setState(() => letter = l);
            scroll.jumpTo(min(o, scroll.position.maxScrollExtent));
          },
        ),
      ],
    );
  }
}

class _AppRow extends StatefulWidget {
  const _AppRow(this.app, {required this.height});

  final AppInfo app;
  final double height;

  @override
  State<_AppRow> createState() => _AppRowState();
}

class _AppRowState extends State<_AppRow> {
  bool focused = false;

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return FocusableActionDetector(
      onFocusChange: (f) => setState(() => focused = f),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => store.launch(app.packageName)),
        MenuIntent: CallbackAction<MenuIntent>(onInvoke: (_) => showAppMenu(context, app)),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => store.launch(app.packageName),
        onLongPress: () => showAppMenu(context, app),
        child: Container(
          height: widget.height,
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFF2A2238))),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  app.name,
                  style: _sans(22, color: focused ? Px.accent : Px.fg),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (store.isPinned(app.packageName)) Text('FIJADA', style: _mono(11)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Índice A–Z vertical: tocar o deslizar salta a esa letra.
class _Scrubber extends StatelessWidget {
  const _Scrubber({required this.present, required this.selected, required this.onPick});

  final Set<String> present;
  final String? selected;
  final void Function(String letter) onPick;

  static final letters = ['#', for (var c = 65; c <= 90; c++) String.fromCharCode(c)];

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      void pick(double y) => onPick(letters[(y / box.maxHeight * letters.length).floor().clamp(0, letters.length - 1)]);
      return Semantics(
        label: 'Índice alfabético',
        child: GestureDetector(
          onTapDown: (d) => pick(d.localPosition.dy),
          onVerticalDragUpdate: (d) => pick(d.localPosition.dy),
          child: Container(
            width: 44,
            decoration: const BoxDecoration(
              border: Border(left: BorderSide(color: Color(0xFF2A2238))),
            ),
            child: Column(
              children: [
                for (final l in letters)
                  Expanded(
                    child: Container(
                      color: l == selected ? Px.accent : null,
                      alignment: Alignment.center,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          l,
                          style: _mono(10, color: l == selected ? Px.bg : (present.contains(l) ? Px.fg : Px.dim)),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

// ─── Consola ─────────────────────────────────────────────────────────────────

/// Consola: apps (las más usadas primero) pensadas para gamepad, en carrusel o en panorámica
/// (grilla de tarjetas, como una biblioteca de juegos). La vista se guarda en la pestaña ('view').
/// Flechas mueven, confirmar o Enter abre, menú fija o quita de INICIO, vista cambia la vista
/// (botones según el layout de `pad.dart`). L1/R1 cambian de pestaña (lo maneja la shell).
class ConsolaPage extends StatefulWidget {
  const ConsolaPage(this.tab, {super.key});

  final int tab;

  @override
  State<ConsolaPage> createState() => _ConsolaPageState();
}

class _ConsolaPageState extends State<ConsolaPage> with SingleTickerProviderStateMixin {
  static const gap = 16.0;
  static const pad = EdgeInsets.fromLTRB(0, Px.unit * 2, 6, 6); // lugar para el flote y la sombra

  var pager = PageController(viewportFraction: 0.36);
  final grid = ScrollController();
  bool pano = false;
  int cols = 1; // de la panorámica, calculadas en cada build
  double rowH = 0;
  int page = 0;
  bool launching = false;
  // un ciclo de 2,4 s mueve todo: flote (3 por ciclo), brillo (primer 40 %) y «PULSÁ A»
  late final clock = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));
  bool still = false; // "quitar animaciones" de Android

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    still = MediaQuery.disableAnimationsOf(context);
    still ? clock.stop() : clock.repeat();
  }

  @override
  void dispose() {
    clock.dispose();
    pager.dispose();
    grid.dispose();
    super.dispose();
  }

  void go(int i) {
    if (!pano) {
      // easeOutBack: se pasa un poco y vuelve, como un carrusel de fichín
      still
          ? pager.jumpToPage(i)
          : pager.animateToPage(i, duration: const Duration(milliseconds: 260), curve: Curves.easeOutBack);
      return;
    }
    setState(() => page = i);
    if (!grid.hasClients) return;
    // scrollea lo justo para que la fila elegida quede entera a la vista
    final pos = grid.position;
    final top = i ~/ cols * (rowH + gap), bottom = top + rowH + pad.vertical - pos.viewportDimension;
    final to = (top < pos.pixels ? top : max(pos.pixels, bottom)).clamp(0.0, pos.maxScrollExtent);
    if (to == pos.pixels) return;
    still ? grid.jumpTo(to) : grid.animateTo(to, duration: const Duration(milliseconds: 150), curve: Curves.easeOut);
  }

  /// Persianas de pixel con el nombre y después abre. Sin animaciones, abre directo.
  void open(AppInfo app) {
    if (still) {
      store.launch(app.packageName);
      return;
    }
    if (launching) return;
    launching = true;
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _Blinds(
        app.name,
        onDone: () {
          store.launch(app.packageName);
          // un rato tapado así no asoma el launcher mientras abre la app
          Future.delayed(const Duration(milliseconds: 600), () {
            entry.remove();
            launching = false;
          });
        },
      ),
    );
    Overlay.of(context).insert(entry);
  }

  // sin alignment: dentro de un Wrap, un Container alineado se estira a todo el ancho
  Widget _key(String k, {Color? color}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      border: Border.all(color: color ?? Px.fg, width: Px.unit * 2),
    ),
    child: Text(
      k,
      style: Px.text.copyWith(fontSize: Px.sz(20), color: color ?? Px.fg),
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([store, tabStore]),
    builder: (context, _) {
      final apps = store.byUse;
      if (apps.isEmpty || widget.tab >= tabStore.tabs.length) return const SizedBox();
      final nowPano = tabStore.tabs[widget.tab]['view'] == 'pano';
      if (nowPano != pano) {
        pano = nowPano;
        if (pano) {
          WidgetsBinding.instance.addPostFrameCallback((_) => go(page)); // que la elegida quede a la vista
        } else {
          // el PageView se arma de nuevo: un controller nuevo arranca en la app elegida
          pager.dispose();
          pager = PageController(viewportFraction: 0.36, initialPage: page);
        }
      }
      final current = apps[page.clamp(0, apps.length - 1)];
      return Focus(
        autofocus: true,
        onKeyEvent: (node, e) {
          if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
          final k = e.logicalKey;
          if (k == LogicalKeyboardKey.arrowLeft) {
            go(max(0, page - 1));
          } else if (k == LogicalKeyboardKey.arrowRight) {
            go(min(apps.length - 1, page + 1));
          } else if (pano && k == LogicalKeyboardKey.arrowUp) {
            go(page >= cols ? page - cols : page);
          } else if (pano && k == LogicalKeyboardKey.arrowDown) {
            go(min(apps.length - 1, page + cols));
          } else if (k == padKey(PadButton.view)) {
            tabStore.toggleView(widget.tab);
          } else if (isOk(k)) {
            open(current);
          } else if (k == padKey(PadButton.menu)) {
            store.togglePin(current.packageName);
          } else {
            return KeyEventResult.ignored;
          }
          return KeyEventResult.handled;
        },
        child: Column(
          children: [
            Expanded(
              child: pano
                  ? _grid(apps)
                  : PageView.builder(
                      controller: pager,
                      itemCount: apps.length,
                      onPageChanged: (i) => setState(() => page = i),
                      itemBuilder: (context, i) => AnimatedBuilder(
                        animation: pager,
                        builder: (context, _) {
                          final p = pager.hasClients && pager.position.haveDimensions ? pager.page! : page.toDouble();
                          final d = (p - i).abs().clamp(0.0, 1.0);
                          return Center(
                            child: Transform.scale(scale: 1 - d * 0.3, child: _card(context, apps[i], i == page, i)),
                          );
                        },
                      ),
                    ),
            ),
            const SizedBox(height: 12),
            AnimatedBuilder(
              animation: clock,
              builder: (context, _) => Opacity(
                opacity: !still && (clock.value * 4).floor().isOdd ? 0 : 1,
                child: Text('PULSÁ ${padLabel(PadButton.ok)}', style: Px.text.copyWith(color: Px.accent)),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _key(padLabel(PadButton.ok), color: Px.accent),
                Text('Abrir', style: Px.text),
                _key(padLabel(PadButton.menu)),
                Text(store.isPinned(current.packageName) ? 'Quitar' : 'Fijar', style: Px.text),
                _key(padLabel(PadButton.view)),
                Text(pano ? 'Carrusel' : 'Panorámica', style: Px.text),
                _key(shoulderLabel),
                Text('Pestaña', style: Px.text),
                Text('${page + 1} / ${apps.length}', style: Px.text.copyWith(color: Px.dimText)),
              ],
            ),
          ],
        ),
      );
    },
  );

  /// Panorámica: grilla de tarjetas, al menos 2 filas a la vista; scrollea hacia abajo.
  Widget _grid(List<AppInfo> apps) => LayoutBuilder(
    builder: (context, box) {
      // columnas de ~140 de ancho; el alto sale de la tarjeta, pero siempre entran 2 filas
      final w = box.maxWidth - pad.horizontal;
      cols = max(2, ((w + gap) / (140 + gap)).round());
      rowH = min((w - (cols - 1) * gap) / cols / 0.8, (box.maxHeight - gap - pad.vertical) / 2);
      return GridView.builder(
        controller: grid,
        padding: pad,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisExtent: rowH,
          mainAxisSpacing: gap,
          crossAxisSpacing: gap,
        ),
        itemCount: apps.length,
        itemBuilder: (context, i) => Center(child: _card(context, apps[i], i == page, i)),
      );
    },
  );

  Widget _card(BuildContext context, AppInfo app, bool selected, int i) {
    final card = GestureDetector(
      onTap: () => selected ? open(app) : go(i),
      onLongPress: () => showAppMenu(context, app),
      child: AspectRatio(
        aspectRatio: 0.8,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Px.bg,
            border: Border.all(color: selected ? Px.accent : Px.dim, width: Px.unit * 2),
            boxShadow: const [BoxShadow(color: Px.shadow, offset: Offset(6, 6))],
          ),
          child: Column(
            children: [
              Expanded(child: FittedBox(child: PixelIcon(app.icon))),
              const SizedBox(height: 8),
              Text(
                '${selected ? '>' : ''}${app.name}',
                style: Px.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
    if (!selected || still) return card;
    // la elegida flota en 2 cuadros, como un sprite, y la cruza un brillo cada ciclo
    return AnimatedBuilder(
      animation: clock,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, (clock.value * 6).floor().isOdd ? -Px.unit * 2 : 0),
        child: CustomPaint(foregroundPainter: _ShinePainter(clock.value), child: child),
      ),
      child: card,
    );
  }
}

/// Franja diagonal clara que cruza la tarjeta en 9 saltos durante el primer 40 % del ciclo.
class _ShinePainter extends CustomPainter {
  _ShinePainter(this.t);

  final double t; // 0..1 del ciclo

  int get step => t < 0.4 ? (t / 0.4 * 9).floor() : -1;

  @override
  void paint(Canvas canvas, Size size) {
    if (step < 0) return;
    final x = -0.3 * size.width + step / 8 * 1.6 * size.width;
    const w = 14.0, lean = 20.0;
    canvas.clipRect(Offset.zero & size);
    canvas.drawPath(
      Path()
        ..moveTo(x + lean, 0)
        ..lineTo(x + lean + w, 0)
        ..lineTo(x + w, size.height)
        ..lineTo(x, size.height)
        ..close(),
      Paint()..color = Px.fg.withValues(alpha: 0.22),
    );
  }

  @override
  bool shouldRepaint(_ShinePainter old) => old.step != step;
}

/// Persianas: 10 franjas que bajan en 4 saltos, una tras otra, y el nombre de la app. Llama a
/// [onDone] a los 450 ms.
class _Blinds extends StatelessWidget {
  const _Blinds(this.name, {required this.onDone});

  final String name;
  final VoidCallback onDone;

  static const bars = 10;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 450),
    duration: const Duration(milliseconds: 450),
    onEnd: onDone,
    builder: (context, ms, _) => Stack(
      fit: StackFit.expand,
      children: [
        Column(
          children: [
            for (var i = 0; i < bars; i++)
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: FractionallySizedBox(
                    widthFactor: 1,
                    heightFactor: (((ms - i * 25) / 200).clamp(0.0, 1.0) * 4).floor() / 4,
                    child: ColoredBox(color: Px.fg),
                  ),
                ),
              ),
          ],
        ),
        if (ms > 350)
          Center(
            child: Text(
              '>${name.toUpperCase()}',
              style: Px.big.copyWith(color: Px.bg),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    ),
  );
}

// ─── Órbita ──────────────────────────────────────────────────────────────────

/// Órbita: las apps orbitan la luna, más cerca = más usada (3 + 5 + 8 por capa).
/// Tocá una app para abrirla, o mantené la luna y arrastrá hacia una. CAPA muestra las siguientes 16.
/// Las letras de abajo resaltan las apps que empiezan con esa letra.
class OrbitaPage extends StatefulWidget {
  const OrbitaPage({super.key});

  @override
  State<OrbitaPage> createState() => _OrbitaPageState();
}

class _OrbitaPageState extends State<OrbitaPage> with SingleTickerProviderStateMixin {
  static const rings = [3, 5, 8];
  static const turns = [20.0, 35.0, 60.0]; // segundos por vuelta de cada anillo: el de adentro va más rápido
  static const perLayer = 16;
  static const moonR = 30.0;
  static const openTime = 0.45; // segundos de la animación de abrir

  int layer = 0;
  Offset? drag; // dónde está el dedo mientras se arrastra desde la luna (coordenadas del cielo)
  String? letter;
  String? focused; // planeta con foco del D-pad: la órbita se frena para no escaparse del cursor
  ({AppInfo app, double at})? opening; // app que se está abriendo y cuándo empezó

  late final _ticker = createTicker(_tick);
  Duration _last = Duration.zero;
  final _time = ValueNotifier(0.0); // segundos con la pestaña a la vista: estrellas, luna y apertura
  double _orbit = 0; // segundos de giro acumulados (sin contar los frenados)

  void _tick(Duration elapsed) {
    if (drag == null && focused == null && opening == null) _orbit += (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    _time.value = elapsed.inMicroseconds / 1e6;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // "quitar animaciones" de Android: queda la órbita quieta de siempre
    if (MediaQuery.disableAnimationsOf(context)) {
      _ticker.stop();
    } else if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  /// Estela, el planeta cae en la luna, destello, y recién ahí abre.
  void open(AppInfo app) {
    if (!_ticker.isActive) {
      store.launch(app.packageName);
      return;
    }
    if (opening != null) return;
    opening = (app: app, at: _time.value);
    Future.delayed(Duration(milliseconds: (openTime * 1000).round()), () {
      store.launch(app.packageName);
      if (mounted) opening = null;
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final all = store.byUse;
      final layers = max(1, min(4, (all.length / perLayer).ceil()));
      final l = layer % layers;
      final apps = all.skip(l * perLayer).take(perLayer).toList();
      final letters = {for (final a in all) initialOf(a.name)}.toList()..sort();
      final found = letter == null ? <AppInfo>[] : all.where((a) => initialOf(a.name) == letter).take(6).toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'más cerca de la luna = más usada',
                  style: Px.text.copyWith(fontSize: Px.sz(18), color: Px.dimText),
                ),
              ),
              PixelTile(label: 'CAPA ${l + 1}/$layers', onTap: () => setState(() => layer = (l + 1) % layers)),
            ],
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) => ValueListenableBuilder(
                valueListenable: _time,
                builder: (context, t, _) => _sky(context, box.biggest, apps, t),
              ),
            ),
          ),
          Text(
            'tocá una app, o mantené la luna y arrastrá',
            textAlign: TextAlign.center,
            style: Px.text.copyWith(fontSize: Px.sz(18), color: Px.dimText),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final c in letters)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: SizedBox(
                      width: 52, // menos y la letra no entra entre el borde y el padding

                      child: PixelTile(
                        vertical: true,
                        label: c,
                        selected: c == letter,
                        onTap: () => setState(() => letter = c == letter ? null : c),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (found.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final a in found)
                  PixelTile(
                    label: a.name,
                    onTap: () => store.launch(a.packageName),
                    onLongPress: () => showAppMenu(context, a),
                  ),
              ],
            ),
          ],
        ],
      );
    },
  );

  Widget _sky(BuildContext context, Size size, List<AppInfo> apps, double t) {
    Offset snap(Offset o) => Offset((o.dx / Px.unit).round() * Px.unit, (o.dy / Px.unit).round() * Px.unit);
    final c = snap(Offset(size.width / 2, size.height / 2));
    final r = max(0.0, min(size.width, size.height) / 2 - 20);
    final radii = [r * 0.42, r * 0.71, r];
    const sizes = [48.0, 38.0, 30.0];
    const starts = [-pi / 2, -pi / 3, -pi * 0.6];
    final planets = <({AppInfo app, Offset pos, double size, int ring})>[];
    var k = 0;
    for (var ring = 0; ring < rings.length; ring++) {
      for (var j = 0; j < rings[ring] && k < apps.length; j++, k++) {
        final a = starts[ring] + j * 2 * pi / rings[ring] + _orbit * 2 * pi / turns[ring];
        planets.add((app: apps[k], pos: snap(c + Offset(cos(a), sin(a)) * radii[ring]), size: sizes[ring], ring: ring));
      }
    }
    // la app más cercana al dedo, si está a tiro
    ({AppInfo app, Offset pos, double size, int ring})? hit(Offset? p) {
      if (p == null) return null;
      final near = planets.where((pl) => (pl.pos - p).distance < pl.size / 2 + 24).toList()
        ..sort((a, b) => (a.pos - p).distance.compareTo((b.pos - p).distance));
      return near.firstOrNull;
    }

    // apertura en 3 tramos: la estela llega (0–0.35), el planeta cae en la luna (0.35–0.75), destello (0.75–1)
    final f = opening == null ? 0.0 : ((t - opening!.at) / openTime).clamp(0.0, 1.0);
    final openingPlanet = planets.where((p) => p.app == opening?.app).firstOrNull;
    var trail = drag == null ? null : (hit(drag)?.pos ?? drag!);
    if (openingPlanet != null && f < 0.75) trail = Offset.lerp(c, openingPlanet.pos, min(1, f / 0.35));
    final target = openingPlanet ?? hit(drag);
    final falling = openingPlanet != null && f > 0.35;
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _SkyPainter(
              c,
              radii,
              moonR,
              moonPhase(DateTime.now()),
              trail,
              t,
              f > 0.75 ? (f - 0.75) / 0.25 : null,
            ),
          ),
        ),
        Positioned(
          left: c.dx - moonR,
          top: c.dy - moonR,
          width: moonR * 2,
          height: moonR * 2,
          child: Semantics(
            label: 'Luna: mantené y arrastrá hacia una app',
            child: RawGestureDetector(
              behavior: HitTestBehavior.opaque, // el hijo está vacío: sin esto la luna no recibe el toque
              gestures: {
                LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
                  () => LongPressGestureRecognizer(duration: const Duration(milliseconds: 150)),
                  (rec) => rec
                    ..onLongPressStart = ((_) => setState(() => drag = c))
                    ..onLongPressMoveUpdate = ((d) => setState(() => drag = c + d.localOffsetFromOrigin))
                    ..onLongPressEnd = ((_) {
                      final t = hit(drag);
                      setState(() => drag = null);
                      if (t != null) open(t.app);
                    }),
                ),
              },
              child: const SizedBox.expand(),
            ),
          ),
        ),
        for (final p in planets) ...[
          if (!(p == openingPlanet && f >= 0.75))
            _planet(p, c, snap, p == openingPlanet && falling ? (f - 0.35) / 0.4 : 0, target),
          if (p.ring == 0 && !(p == openingPlanet && falling))
            Positioned(
              left: p.pos.dx - 50,
              top: p.pos.dy + p.size / 2 + 2,
              width: 100,
              child: Text(
                p.app.name,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Px.text.copyWith(fontSize: Px.sz(16)),
              ),
            ),
        ],
        if (target != null && !falling)
          // arriba del planeta, centrada y con fondo para no pisar a los vecinos
          Positioned(
            left: (target.pos.dx - 80).clamp(0.0, max(0.0, size.width - 160)),
            top: target.pos.dy - target.size / 2 - 30,
            width: 160,
            child: Center(
              child: Container(
                color: Px.bg,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  '>${target.app.name.toUpperCase()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Px.text.copyWith(color: Px.accent),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Un planeta en su lugar; con [fall] > 0 cae hacia la luna achicándose.
  Widget _planet(
    ({AppInfo app, Offset pos, double size, int ring}) p,
    Offset c,
    Offset Function(Offset) snap,
    double fall,
    ({AppInfo app, Offset pos, double size, int ring})? target,
  ) {
    final pos = snap(Offset.lerp(p.pos, c, fall)!);
    final s = max(Px.unit * 4, (p.size * (1 - fall) / (Px.unit * 2)).round() * Px.unit * 2);
    return Positioned(
      left: pos.dx - s / 2,
      top: pos.dy - s / 2,
      width: s,
      height: s,
      child: _Planet(
        p.app,
        hot: target?.app == p.app || (letter != null && initialOf(p.app.name) == letter),
        faded: letter != null && initialOf(p.app.name) != letter,
        onOpen: () => open(p.app),
        onFocus: (on) => focused = on ? p.app.packageName : (focused == p.app.packageName ? null : focused),
      ),
    );
  }
}

class _Planet extends StatefulWidget {
  const _Planet(this.app, {required this.hot, required this.faded, required this.onOpen, required this.onFocus});

  final AppInfo app;
  final bool hot;
  final bool faded;
  final VoidCallback onOpen;
  final ValueChanged<bool> onFocus;

  @override
  State<_Planet> createState() => _PlanetState();
}

class _PlanetState extends State<_Planet> {
  bool focused = false;

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return Semantics(
      label: app.name,
      button: true,
      child: FocusableActionDetector(
        onFocusChange: (f) {
          widget.onFocus(f);
          setState(() => focused = f);
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onOpen()),
          MenuIntent: CallbackAction<MenuIntent>(onInvoke: (_) => showAppMenu(context, app)),
        },
        child: GestureDetector(
          onTap: widget.onOpen,
          onLongPress: () => showAppMenu(context, app),
          child: Opacity(
            opacity: widget.faded ? 0.35 : 1,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Px.bg,
                border: Border.all(color: widget.hot || focused ? Px.accent : Px.dim, width: Px.unit),
                boxShadow: const [BoxShadow(color: Px.shadow, offset: Offset(3, 3))],
              ),
              child: FittedBox(child: PixelIcon(app.icon)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Estrellas que titilan, anillos punteados, la luna con su fase y su latido, la estela del
/// arrastre y el destello al abrir una app.
class _SkyPainter extends CustomPainter {
  _SkyPainter(this.c, this.radii, this.moonR, this.phase, this.trailTo, this.t, this.flash);

  final Offset c;
  final List<double> radii;
  final double moonR;
  final int phase; // 0..7 (0 = nueva, 4 = llena)
  final Offset? trailTo;
  final double t; // segundos, para titilar y latir a saltos
  final double? flash; // 0..1 mientras destella

  // posiciones relativas (0..1) y desfase de cada estrella; fijas para que no salten entre frames
  static final _stars = () {
    final r = Random(7);
    return [for (var i = 0; i < 40; i++) (x: r.nextDouble(), y: r.nextDouble(), p: r.nextInt(7))];
  }();

  @override
  void paint(Canvas canvas, Size size) {
    final dot = Paint();
    for (final s in _stars) {
      final k = ((t * 1.6).floor() + s.p) % 7;
      if (k == 1) continue; // apagada
      dot.color = k == 0 ? Px.fg : Px.dim;
      final x = (s.x * size.width / Px.unit).floor() * Px.unit, y = (s.y * size.height / Px.unit).floor() * Px.unit;
      canvas.drawRect(Rect.fromLTWH(x, y, Px.unit, Px.unit), dot);
    }
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = Px.unit;
    for (final (i, r) in radii.indexed) {
      ring.color = [Px.dim, const Color(0xFF4E4060), const Color(0xFF3A3048)][i];
      final dashes = max(1, (2 * pi * r / 10).floor());
      for (var d = 0; d < dashes; d++) {
        canvas.drawArc(Rect.fromCircle(center: c, radius: r), d * 2 * pi / dashes, 2 * pi / dashes * 0.6, false, ring);
      }
    }
    if (trailTo != null) {
      final trail = Paint()
        ..color = Px.accent
        ..strokeWidth = 3;
      final v = trailTo! - c;
      final steps = (v.distance / 10).floor();
      for (var s = 0; s < steps; s++) {
        canvas.drawLine(c + v * (s / steps), c + v * ((s + 0.6) / steps), trail);
      }
    }
    // latido: un anillo que se aleja de la luna en 3 saltos
    canvas.drawCircle(c, moonR + 6 + ((t * 2.5).floor() % 3) * 4, ring..color = const Color(0xFF3A3048));
    // luna: disco claro y un disco oscuro corrido según la fase (creciente: la sombra se va a la izquierda)
    final moon = Rect.fromCircle(center: c, radius: moonR);
    final p = phase / 8;
    final shift = p <= 0.5 ? -4 * moonR * p : 4 * moonR * (1 - p);
    canvas.save();
    canvas.clipPath(Path()..addOval(moon));
    canvas.drawOval(moon, Paint()..color = Px.fg);
    canvas.drawCircle(c + Offset(shift, 0), moonR, Paint()..color = Px.bg);
    canvas.restore();
    canvas.drawCircle(c, moonR, ring..color = Px.dim);
    // destello: cuadros que se abren desde la luna en 4 saltos y un fogonazo al final
    if (flash != null) {
      final step = (flash! * 5).floor();
      if (step < 4) {
        final half = moonR + step * size.longestSide / 5;
        canvas.drawRect(
          Rect.fromCenter(center: c, width: half * 2, height: half * 2),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = Px.unit * 2
            ..color = Px.accent,
        );
      } else {
        canvas.drawRect(Offset.zero & size, Paint()..color = Px.accent.withValues(alpha: 0.35));
      }
    }
  }

  @override
  bool shouldRepaint(_SkyPainter old) =>
      old.trailTo != trailTo || old.c != c || old.phase != phase || old.t != t || old.flash != flash;
}
