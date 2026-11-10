import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'apps.dart';
import 'claude.dart';
import 'gu.dart';
import 'pad.dart';
import 'pages.dart';
import 'tabs.dart';
import 'trinkets.dart';
import 'utilities.dart';
import 'ui.dart';

void main() => runApp(const App());

/// En un build y no en main: al cambiar de estilo se rearma y toma el tema nuevo.
class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Pixel Launcher',
    debugShowCheckedModeBanner: false,
    navigatorKey: navigatorKey, // para los pedidos de permiso de Claude (claude.dart)
    theme: Px.theme(),
    // por encima del Navigator: así los botones del mando también andan en los diálogos
    builder: (context, child) => ListenableBuilder(
      listenable: store,
      builder: (_, _) => Shortcuts(shortcuts: padShortcuts(), child: child!),
    ),
    home: const Shell(),
  );
}

/// La pantalla del launcher: trinkets, barra de pestañas y páginas.
/// Las pestañas del usuario salen de [tabStore]; SYS y "+" siempre van al final y no se borran.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  final pager = PageController();
  int current = 0;
  int count = 0; // cantidad de pestañas en el último build
  final _chips = <int, GlobalKey>{};
  GlobalKey _chip(int i) => _chips.putIfAbsent(i, GlobalKey.new);
  // ponytail: recarga al volver al launcher; canal nativo de PACKAGE_ADDED/REMOVED si se nota lento.
  late final AppLifecycleListener _life;

  @override
  void initState() {
    super.initState();
    _life = AppLifecycleListener(onResume: store.load);
    store.load();
    tabStore.load();
    startMcp();
    HardwareKeyboard.instance.addHandler(_pad);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_pad);
    _life.dispose();
    super.dispose();
  }

  /// L1/R1 cambian de pestaña y volver cierra el diálogo abierto o hace lo de ATRÁS. Global y no
  /// con Shortcuts: al cambiar de página se destruye el widget con foco y, si la nueva no enfoca
  /// nada, un atajo dentro del árbol ya no recibe teclas.
  bool _pad(KeyEvent e) {
    if (e is! KeyDownEvent) return false;
    if (e.logicalKey == padKey(PadButton.back)) {
      Navigator.of(context).maybePop();
      return true;
    }
    final d = e.logicalKey == LogicalKeyboardKey.gameButtonLeft1
        ? -1
        : e.logicalKey == LogicalKeyboardKey.gameButtonRight1
        ? 1
        : 0;
    if (d == 0) return false;
    go(current + d);
    return true;
  }

  void go(int i) {
    webFocus.value = null;
    pager.jumpToPage(i.clamp(0, count - 1));
  }

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: Listenable.merge([tabStore, webFocus]), builder: _build);

  Widget _build(BuildContext context, _) {
    final all = [
      for (final (i, t) in tabStore.tabs.indexed)
        (
          t['name'] as String,
          KeyedSubtree(key: ObjectKey(t), child: (tabKinds[t['kind']] ?? tabKinds['custom']!).page(i)),
        ),
      ('SYS', const SystemPage()),
      ('+', AddTabPage(onOpen: go)),
    ];
    count = all.length;
    // un solo renglón que se desliza; con muchas pestañas no se come la pantalla
    final bar = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(right: Px.unit * 2, bottom: Px.unit * 2), // lugar para las sombras
      child: Row(
        children: [
          for (final (i, (name, _)) in all.indexed)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: PixelTile(
                key: _chip(i),
                label: name,
                selected: i == current,
                onTap: () => go(i),
                // SYS y "+" no tienen menú: no se renombran ni se borran
                onLongPress: i < tabStore.tabs.length ? () => showTabMenu(context, i, go) : null,
              ),
            ),
        ],
      ),
    );
    final pages = Expanded(
      child: PageView(
        controller: pager,
        physics: webFocus.value != null ? const NeverScrollableScrollPhysics() : null,
        onPageChanged: (i) {
          setState(() => current = i);
          // que la pestaña actual quede a la vista en la barra
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final chip = _chips[i]?.currentContext;
            if (chip != null) {
              Scrollable.ensureVisible(chip, alignment: 0.5, duration: const Duration(milliseconds: 150));
            }
          });
        },
        children: [for (final (_, page) in all) _PageScope(child: page)],
      ),
    );
    return PopScope(
      canPop: false, // un launcher nunca "sale": atrás suelta la web con foco, o vuelve a la primera pestaña
      onPopInvokedWithResult: (_, _) => webFocus.value != null ? webFocus.value = null : go(0),
      child: Scaffold(
        resizeToAvoidBottomInset: false, // el teclado tapa, no achica el launcher
        body: Stack(
          children: [
            if (Px.gu) const Positioned.fill(child: HexBackdrop()),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: tabStore.tabsBottom
                      ? [const TrinketBar(), const SizedBox(height: 12), pages, const SizedBox(height: 12), bar]
                      : [const TrinketBar(), const SizedBox(height: 12), bar, const SizedBox(height: 12), pages],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cada página en su propio FocusScope: al entrar, su autofocus le gana al foco que haya quedado
/// en la barra de pestañas. En los bordes, las flechas siguen hacia la barra y APAGAR.
class _PageScope extends StatefulWidget {
  const _PageScope({required this.child});

  final Widget child;

  @override
  State<_PageScope> createState() => _PageScopeState();
}

class _PageScopeState extends State<_PageScope> {
  final node = FocusScopeNode(
    debugLabel: 'página',
    directionalTraversalEdgeBehavior: TraversalEdgeBehavior.parentScope,
  );

  @override
  void dispose() {
    node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FocusScope(node: node, child: widget.child);
}
