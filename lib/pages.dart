import 'dart:convert';
import 'dart:math';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:installed_apps/installed_apps.dart';

import 'apps.dart';
import 'gu.dart';
import 'pad.dart';
import 'tabs.dart';
import 'ui.dart';

/// Tile de app: tap abre, long-press abre el menú de la app.
Widget appTile(BuildContext context, AppInfo app, {bool vertical = false, bool autofocus = false, String match = ''}) =>
    PixelTile(
      label: app.name,
      match: match,
      leading: PixelIcon(app.icon),
      vertical: vertical,
      autofocus: autofocus,
      onTap: () => store.launch(app.packageName),
      onLongPress: () => showAppMenu(context, app),
    );

void showAppMenu(BuildContext context, AppInfo app) => showPixelMenu(context, app.name, [
  (store.isPinned(app.packageName) ? 'Quitar de INICIO' : 'Fijar en INICIO', () => store.togglePin(app.packageName)),
  ('Info de la app', () => InstalledApps.openSettings(app.packageName)),
]);

/// INICIO: apps fijadas en grilla. En las dos orientaciones llena filas de izquierda a derecha
/// y suma filas hacia abajo (scroll vertical). El alto de fila hace que entren 2 filas en
/// pantalla; en vertical eso deja 2 columnas (grilla doble), en horizontal las que entren.
class PinnedPage extends StatelessWidget {
  const PinnedPage({super.key});

  static const row = 120.0; // alto máximo de cada fila: ajustá el tamaño de la grilla acá
  static const aspect = 0.8; // alto/ancho de cada celda: menor = más ancha
  static const gap = 8.0;
  static const shadow = Px.unit * 2;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final apps = store.pinnedApps;
      if (apps.isEmpty) {
        return Center(
          child: Text(
            'Mantené apretada una app en APPS\npara fijarla acá',
            textAlign: TextAlign.center,
            style: Px.text.copyWith(color: Px.dim),
          ),
        );
      }
      return LayoutBuilder(
        builder: (context, box) {
          final rowH = min(row, (box.maxHeight - gap - shadow) / 2);
          final cellW = rowH / aspect;
          return GridView.builder(
            padding: const EdgeInsets.only(right: shadow, bottom: shadow),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: max(1, (box.maxWidth + gap) ~/ (cellW + gap)),
              mainAxisExtent: rowH,
              mainAxisSpacing: gap,
              crossAxisSpacing: gap,
            ),
            itemCount: apps.length,
            itemBuilder: (context, i) => appTile(context, apps[i], vertical: true, autofocus: i == 0),
          );
        },
      );
    },
  );
}

/// Lista de todas las apps con búsqueda.
class AppsPage extends StatefulWidget {
  const AppsPage({super.key});

  @override
  State<AppsPage> createState() => _AppsPageState();
}

class _AppsPageState extends State<AppsPage> {
  String query = '';

  @override
  Widget build(BuildContext context) => Column(
    children: [
      TextField(style: Px.text, decoration: Px.input('buscar...'), onChanged: (v) => setState(() => query = v)),
      const SizedBox(height: 8),
      Expanded(
        child: ListenableBuilder(
          listenable: store,
          builder: (context, _) {
            final q = query.toLowerCase();
            final shown = store.apps.where((a) => a.name.toLowerCase().contains(q)).toList();
            return ListView.separated(
              itemCount: shown.length,
              separatorBuilder: (_, _) => const SizedBox(height: 4),
              itemBuilder: (context, i) => appTile(context, shown[i], autofocus: i == 0),
            );
          },
        ),
      ),
    ],
  );
}

/// Copia al portapapeles el uso registrado (aperturas por app y por hora), las fijadas y las pestañas,
/// para pegarlo donde quieras y analizarlo.
Future<void> copyUsage() async {
  final names = {for (final a in store.apps) a.packageName: a.name};
  final data = {
    'exportado': DateTime.now().toIso8601String(),
    'apps': [
      for (final e in store.usage.entries)
        {'paquete': e.key, 'nombre': names[e.key], 'total': store.uses(e.key), 'porHora': e.value},
    ]..sort((a, b) => (b['total'] as int) - (a['total'] as int)),
    'fijadas': store.pinned,
    'pestañas': [for (final t in tabStore.tabs) '${t['kind']}:${t['name']}'],
    'pestañasAbajo': tabStore.tabsBottom,
  };
  await Clipboard.setData(ClipboardData(text: const JsonEncoder.withIndent('  ').convert(data)));
  InstalledApps.toast('Datos de uso copiados', true);
}

/// Página de sistema (equivalente a la pestaña Settings de TrinketOS).
class SystemPage extends StatelessWidget {
  const SystemPage({super.key});

  @override
  Widget build(BuildContext context) {
    final menu = ListView(
      children: [
        PixelTile(
          autofocus: true,
          label: 'Elegir launcher por defecto',
          onTap: () => const AndroidIntent(action: 'android.settings.HOME_SETTINGS').launch(),
        ),
        const SizedBox(height: 4),
        PixelTile(
          label: 'Ajustes de Android',
          onTap: () => const AndroidIntent(action: 'android.settings.SETTINGS').launch(),
        ),
        const SizedBox(height: 4),
        ListenableBuilder(
          listenable: store,
          builder: (context, _) {
            final name = store.apps.where((a) => a.packageName == store.browser).firstOrNull?.name;
            return PixelTile(
              label: 'Navegador: ${name ?? 'del sistema'}',
              onTap: () => showPixelMenu(context, 'Navegador para webs', [
                ('Del sistema', () => store.setBrowser(null)),
                for (final a in store.apps) (a.name, () => store.setBrowser(a.packageName)),
              ]),
            );
          },
        ),
        const SizedBox(height: 4),
        ListenableBuilder(
          listenable: store,
          builder: (context, _) => PixelTile(
            label: 'Mando: ${padLayouts[store.pad]?.name ?? store.pad}',
            onTap: () => showPixelMenu(context, 'Mando (en Nintendo confirma el botón de la derecha)', [
              for (final MapEntry(key: k, value: l) in padLayouts.entries) (l.name, () => store.setPad(k)),
            ]),
          ),
        ),
        const SizedBox(height: 4),
        ListenableBuilder(
          listenable: tabStore,
          builder: (context, _) => PixelTile(
            label: 'Pestañas: ${tabStore.tabsBottom ? 'abajo' : 'arriba'}',
            onTap: () => tabStore.setTabsBottom(!tabStore.tabsBottom),
          ),
        ),
        const SizedBox(height: 4),
        ListenableBuilder(
          listenable: store,
          builder: (context, _) => PixelTile(
            label: 'Estilo: ${Px.gu ? 'G.U.' : 'pixel'}',
            onTap: () => store.setStyle(Px.gu ? PxStyle.pixel : PxStyle.gu),
          ),
        ),
        const SizedBox(height: 4),
        PixelTile(label: 'Copiar datos de uso', onTap: copyUsage),
        const SizedBox(height: 16),
        Text('PIXEL LAUNCHER v0.2', style: Px.text.copyWith(color: Px.dimText)),
      ],
    );
    if (!Px.gu) return menu;
    // G.U.: la espada cruza de fondo y el menú se corre a la derecha para dejarla ver
    return Stack(
      children: [
        const Positioned.fill(child: SwordBackdrop()),
        Align(
          alignment: Alignment.centerRight,
          child: FractionallySizedBox(widthFactor: 0.78, child: menu),
        ),
      ],
    );
  }
}
