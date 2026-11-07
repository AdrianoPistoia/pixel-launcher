import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pages.dart';
import 'ui.dart';
import 'utilities.dart';
import 'views.dart';

/// Tipos de pestaña: nombre por defecto, descripción para el menú de "+" y su página.
/// 'custom' es la pestaña de utilidades. Agregá un tipo nuevo acá.
final tabKinds = <String, ({String name, String about, Widget Function(int tab) page})>{
  'inicio': (name: 'INICIO', about: 'Inicio: apps fijadas', page: (_) => const PinnedPage()),
  'apps': (name: 'APPS', about: 'Apps: lista con búsqueda', page: (_) => const AppsPage()),
  'terminal': (name: 'TERMINAL', about: 'Terminal: sugerencias y comandos', page: (_) => const TerminalPage()),
  'bitacora': (name: 'BITÁCORA', about: 'Bitácora: lista A–Z tranquila', page: (_) => const BitacoraPage()),
  'consola': (name: 'CONSOLA', about: 'Consola: carrusel o grilla', page: (i) => ConsolaPage(i)),
  'orbita': (name: 'ÓRBITA', about: 'Órbita: apps según su uso', page: (_) => const OrbitaPage()),
  'custom': (name: 'UTIL', about: 'Utilidades: hasta 4 widgets', page: (i) => CustomTabPage(i)),
};

// ─── Grilla 2×2 de la pestaña de utilidades ──────────────────────────────────
// Casilleros numerados fila por fila: 0 1 / 2 3. Cada utilidad guarda 'slot' (su casillero de
// arriba a la izquierda) y 'size': '1x1', '2x1' (fila entera), '1x2' (columna entera) o '2x2' (todo).

const widgetSizes = {'1x1': '1 casillero', '2x1': 'fila entera', '1x2': 'columna entera', '2x2': 'toda la pestaña'};

/// Casilleros que ocupa una utilidad de tamaño [size] apoyada en [slot].
Set<int> cellsOf(int slot, String size) {
  final r = slot ~/ 2, c = slot % 2;
  return switch (size) {
    '2x1' => {r * 2, r * 2 + 1},
    '1x2' => {c, c + 2},
    '2x2' => {0, 1, 2, 3},
    _ => {slot},
  };
}

Set<int> _cells(Config w) => cellsOf(w['slot'] as int, w['size'] as String);

List<int> freeCells(List<Config> ws) => [
  for (var c = 0; c < 4; c++)
    if (!ws.any((w) => _cells(w).contains(c))) c,
];

/// ¿Entra la utilidad [i] con ese lugar y tamaño sin pisar a las demás?
bool fits(List<Config> ws, int i, int slot, String size) {
  final mine = cellsOf(slot, size);
  return [
    for (final (j, w) in ws.indexed)
      if (j != i) _cells(w),
  ].every((c) => c.intersection(mine).isEmpty);
}

/// Mueve la utilidad [i] (con su tamaño) a [target]. Las de 1 casillero que estorben pasan
/// al lugar que deja libre. Devuelve false, sin tocar nada, si no hay forma.
bool moveTo(List<Config> ws, int i, int target) {
  final size = ws[i]['size'] as String;
  final to = cellsOf(target, size);
  final freed = (_cells(ws[i]).difference(to).toList())..sort();
  final moves = <int, int>{};
  for (final (j, w) in ws.indexed) {
    if (j == i || _cells(w).intersection(to).isEmpty) continue;
    if (w['size'] != '1x1' || freed.isEmpty) return false;
    moves[j] = freed.removeAt(0);
  }
  ws[i]['slot'] = to.reduce(min);
  for (final MapEntry(key: j, value: slot) in moves.entries) {
    ws[j]['slot'] = slot;
  }
  return true;
}

/// Da lugar y tamaño a utilidades guardadas por versiones que no los tenían, imitando
/// el acomodo de antes (1 = todo, 2 = dos filas, 3 = dos arriba y una fila abajo, 4 = 2×2).
void normalizeWidgets(List<Config> ws) {
  if (ws.every((w) => w.containsKey('slot'))) return;
  const layouts = [
    <(int, String)>[],
    [(0, '2x2')],
    [(0, '2x1'), (2, '2x1')],
    [(0, '1x1'), (1, '1x1'), (2, '2x1')],
    [(0, '1x1'), (1, '1x1'), (2, '1x1'), (3, '1x1')],
  ];
  for (final (i, (slot, size)) in layouts[min(ws.length, 4)].indexed) {
    ws[i]
      ..['slot'] = slot
      ..['size'] = size;
  }
}

/// Pestañas del usuario (todas salvo SYS y "+"). Las de utilidades tienen una grilla de 2×2.
/// Se guardan como JSON: [{kind, name, widgets?: [{type, slot, size, ...config}]}].
class TabStore extends ChangeNotifier {
  List<Map<String, dynamic>> tabs = [];
  bool tabsBottom = false; // barra de pestañas abajo, a mano del pulgar
  late final _prefs = SharedPreferencesAsync();

  /// Pestañas de la primera vez: todas las vistas, más las de utilidades de la versión anterior
  /// (que se guardaban en 'tabs' sin tipo).
  static List<Map<String, dynamic>> initialTabs(String? oldTabs) => [
    for (final kind in ['inicio', 'apps', 'terminal', 'bitacora', 'consola', 'orbita'])
      {'kind': kind, 'name': tabKinds[kind]!.name},
    if (oldTabs != null)
      for (final t in jsonDecode(oldTabs) as List) {...t as Map<String, dynamic>, 'kind': 'custom'},
  ];

  Future<void> load() async {
    final raw = await _prefs.getString('tabs2');
    tabs = raw == null
        ? initialTabs(await _prefs.getString('tabs'))
        : List<Map<String, dynamic>>.from(jsonDecode(raw) as List);
    for (final t in tabs) {
      if (t['kind'] == 'custom') normalizeWidgets((t['widgets'] as List).cast<Config>());
    }
    tabsBottom = await _prefs.getBool('tabsBottom') ?? false;
    notifyListeners();
  }

  Future<void> save() async {
    notifyListeners();
    await _prefs.setString('tabs2', jsonEncode(tabs));
  }

  Future<void> setTabsBottom(bool value) async {
    tabsBottom = value;
    notifyListeners();
    await _prefs.setBool('tabsBottom', value);
  }

  List<dynamic> widgetsOf(int tab) => tabs[tab]['widgets'] as List;

  Future<void> addTab(String kind, String name) {
    tabs.add({'kind': kind, 'name': name, if (kind == 'custom') 'widgets': []});
    return save();
  }

  Future<void> renameTab(int tab, String name) {
    tabs[tab]['name'] = name;
    return save();
  }

  Future<void> removeTab(int tab) {
    for (final w in (tabs[tab]['widgets'] as List?) ?? []) {
      _release(w as Config);
    }
    tabs.removeAt(tab);
    return save();
  }

  Future<void> moveTab(int tab, int delta) {
    tabs.insert(tab + delta, tabs.removeAt(tab));
    return save();
  }

  /// Consola: alterna entre carrusel y panorámica (grilla de tarjetas).
  Future<void> toggleView(int tab) {
    final t = tabs[tab];
    t['view'] == 'pano' ? t.remove('view') : t['view'] = 'pano';
    return save();
  }

  /// Agrega una utilidad de 1 casillero en el casillero libre [slot].
  Future<void> addWidget(int tab, int slot, Config widget) {
    widgetsOf(tab).add({...widget, 'slot': slot, 'size': '1x1'});
    return save();
  }

  /// Libera lo que la utilidad tenga afuera del JSON (por ejemplo, un widget de Android).
  void _release(Config w) => utilities[w['type']]?.remove?.call(w);

  Future<void> removeWidget(int tab, int i) {
    _release(widgetsOf(tab).removeAt(i) as Config);
    return save();
  }

  Future<void> resizeWidget(int tab, int i, String size) {
    final w = widgetsOf(tab)[i] as Config;
    w
      ..['slot'] = cellsOf(w['slot'] as int, size).reduce(min)
      ..['size'] = size;
    return save();
  }

  Future<void> moveWidgetTo(int tab, int i, int target) {
    moveTo(widgetsOf(tab).cast<Config>(), i, target);
    return save();
  }
}

final tabStore = TabStore();

/// Una pestaña de utilidades: grilla de 2×2 donde cada utilidad tiene lugar y tamaño.
/// Los casilleros libres muestran "+ AGREGAR". MAX pone una utilidad en pantalla completa
/// (momentáneo: al salir de la pestaña vuelve a la grilla).
class CustomTabPage extends StatefulWidget {
  const CustomTabPage(this.tab, {super.key});

  final int tab;

  @override
  State<CustomTabPage> createState() => _CustomTabPageState();
}

class _CustomTabPageState extends State<CustomTabPage> {
  static const gap = 8.0;
  static const shadow = Px.unit * 2;
  static const compactBelow = 170.0; // alto de casillero desde el cual los controles van al costado

  int? maxed; // utilidad en pantalla completa

  int get tab => widget.tab;

  void toggleMax(int i) => setState(() => maxed = maxed == i ? null : i);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: tabStore,
    builder: (context, _) {
      if (tab >= tabStore.tabs.length) return const SizedBox();
      final ws = tabStore.widgetsOf(tab).cast<Config>().toList();
      if (maxed != null && maxed! >= ws.length) maxed = null;
      return Padding(
        padding: const EdgeInsets.only(right: shadow, bottom: shadow),
        child: LayoutBuilder(
          builder: (context, box) {
            if (maxed != null) return _frame(context, maxed!, ws, compact: false);
            final cw = (box.maxWidth - gap) / 2;
            final ch = (box.maxHeight - gap) / 2;
            Rect rect(Set<int> cells) {
              final cols = cells.map((c) => c % 2), rows = cells.map((c) => c ~/ 2);
              final c0 = cols.reduce(min), c1 = cols.reduce(max), r0 = rows.reduce(min), r1 = rows.reduce(max);
              return Rect.fromLTWH(
                c0 * (cw + gap),
                r0 * (ch + gap),
                (c1 - c0 + 1) * cw + (c1 - c0) * gap,
                (r1 - r0 + 1) * ch + (r1 - r0) * gap,
              );
            }

            return Stack(
              children: [
                for (final (i, w) in ws.indexed)
                  if (rect(_cells(w)) case final r)
                    Positioned.fromRect(
                      rect: r,
                      child: _frame(context, i, ws, compact: r.height < compactBelow),
                    ),
                for (final f in freeCells(ws))
                  Positioned.fromRect(
                    rect: rect({f}),
                    child: PixelTile(
                      vertical: true,
                      label: '+ AGREGAR',
                      autofocus: ws.isEmpty && f == 0,
                      onTap: () => _add(context, f),
                    ),
                  ),
              ],
            );
          },
        ),
      );
    },
  );

  /// Marco de una utilidad: el título abre el menú; MAX/MIN alterna pantalla completa.
  /// En casilleros bajos (horizontal) los controles van al costado: sobra ancho, falta alto.
  Widget _frame(BuildContext context, int i, List<Config> ws, {required bool compact}) {
    final w = ws[i];
    final u = utilities[w['type']];
    final menu = PixelTile(
      autofocus: i == 0, // que el mando tenga de dónde arrancar
      label: compact ? 'MENÚ' : (u?.label ?? '?').toUpperCase(),
      onTap: () => _menu(context, i, ws),
    );
    final toggle = PixelTile(label: maxed == i ? 'MIN' : 'MAX', onTap: () => toggleMax(i));
    final body = u?.build(w, tabStore.save) ?? const SizedBox();
    return Container(
      decoration: Px.box(),
      padding: const EdgeInsets.all(Px.unit * 2),
      child: compact
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: body),
                const SizedBox(width: 4),
                FittedBox(
                  fit: BoxFit.scaleDown, // en casilleros muy bajos se achica en vez de desbordar
                  child: IntrinsicWidth(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [menu, const SizedBox(height: 4), toggle],
                    ),
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: menu),
                    const SizedBox(width: 4),
                    toggle,
                  ],
                ),
                const SizedBox(height: 4),
                Expanded(child: body),
              ],
            ),
    );
  }

  void _menu(BuildContext context, int i, List<Config> ws) {
    final w = ws[i];
    final u = utilities[w['type']];
    final size = w['size'] as String;
    showPixelMenu(context, u?.label ?? '?', [
      ...?u?.actions?.call(context, w, tabStore.save),
      (maxed == i ? 'Salir de pantalla completa' : 'Pantalla completa', () => toggleMax(i)),
      if (size != '2x2') ('Mover…', () => _pickPosition(context, i, ws)),
      for (final MapEntry(key: s, value: label) in widgetSizes.entries)
        if (s != size && fits(ws, i, cellsOf(w['slot'] as int, s).reduce(min), s))
          ('Tamaño: $label', () => tabStore.resizeWidget(tab, i, s)),
      (
        'Quitar',
        () {
          setState(() => maxed = null);
          tabStore.removeWidget(tab, i);
        },
      ),
    ]);
  }

  /// Mini grilla de 2×2 para elegir adónde mover la utilidad.
  void _pickPosition(BuildContext context, int i, List<Config> ws) {
    final here = _cells(ws[i]);
    bool can(int t) => moveTo(
      [
        for (final w in ws) {...w},
      ],
      i,
      t,
    ); // prueba sobre una copia
    Widget cell(BuildContext ctx, int t) {
      final isHere = here.contains(t);
      final ok = !isHere && can(t);
      return Expanded(
        child: SizedBox(
          height: 64,
          child: PixelTile(
            vertical: true,
            selected: isHere,
            autofocus: ok && t == freeCells(ws).firstOrNull,
            label: isHere ? 'ACÁ' : (ok ? 'MOVER' : '—'),
            onTap: ok
                ? () {
                    Navigator.pop(ctx);
                    tabStore.moveWidgetTo(tab, i, t);
                  }
                : null,
          ),
        ),
      );
    }

    showPixelDialog(
      context,
      'Mover a',
      (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final r in [0, 2]) ...[
            if (r > 0) const SizedBox(height: 8),
            Row(children: [cell(ctx, r), const SizedBox(width: 8), cell(ctx, r + 1)]),
          ],
        ],
      ),
    );
  }

  void _add(BuildContext context, int slot) => showPixelMenu(context, 'Agregar', [
    for (final MapEntry(key: type, value: u) in utilities.entries)
      (
        u.label,
        () async {
          final cfg = await u.create(context);
          if (cfg != null) await tabStore.addWidget(tab, slot, {'type': type, ...cfg});
        },
      ),
  ]);
}

Future<String?> _askName(BuildContext context, String title, [String initial = '']) async =>
    (await askText(context, title, hint: 'nombre', initial: initial))?.trim().toUpperCase();

/// Menú de una pestaña del usuario: ir, renombrar, mover o borrar. Lo usan "+" y la barra de pestañas.
void showTabMenu(BuildContext context, int i, void Function(int tab) onOpen) {
  final name = tabStore.tabs[i]['name'] as String;
  showPixelMenu(context, name, [
    ('Ir', () => onOpen(i)),
    (
      'Renombrar',
      () async {
        final n = await _askName(context, 'Renombrar', name);
        if (n != null && n.isNotEmpty) await tabStore.renameTab(i, n);
      },
    ),
    if (tabStore.tabs[i]['kind'] == 'consola')
      ('Vista: ${tabStore.tabs[i]['view'] == 'pano' ? 'panorámica' : 'carrusel'}', () => tabStore.toggleView(i)),
    if (i > 0) ('Mover antes', () => tabStore.moveTab(i, -1)),
    if (i < tabStore.tabs.length - 1) ('Mover después', () => tabStore.moveTab(i, 1)),
    ('Borrar', () => tabStore.removeTab(i)),
  ]);
}

/// Pestaña "+": crear pestañas de cualquier tipo y administrar las existentes.
class AddTabPage extends StatelessWidget {
  const AddTabPage({super.key, required this.onOpen});

  final void Function(int tab) onOpen;

  /// Abre la pestaña en el próximo frame, cuando la shell ya la agregó.
  void _openLater(int tab) => WidgetsBinding.instance.addPostFrameCallback((_) => onOpen(tab));

  void _create(BuildContext context) => showPixelMenu(context, 'Nueva pestaña', [
    for (final MapEntry(key: kind, value: k) in tabKinds.entries)
      (
        k.about,
        () async {
          final name = kind == 'custom' ? await _askName(context, 'Nombre de la pestaña') : k.name;
          if (name == null || name.isEmpty) return;
          tabStore.addTab(kind, name); // notifica ya; el guardado termina solo
          _openLater(tabStore.tabs.length - 1);
        },
      ),
  ]);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: tabStore,
    builder: (context, _) => ListView(
      children: [
        PixelTile(autofocus: true, label: '+ Nueva pestaña', onTap: () => _create(context)),
        const SizedBox(height: 16),
        if (tabStore.tabs.isNotEmpty)
          Text('TUS PESTAÑAS (también: mantené apretada una arriba)', style: Px.text.copyWith(color: Px.dimText)),
        for (final (i, t) in tabStore.tabs.indexed)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: PixelTile(label: t['name'] as String, onTap: () => showTabMenu(context, i, onOpen)),
          ),
      ],
    ),
  );
}
