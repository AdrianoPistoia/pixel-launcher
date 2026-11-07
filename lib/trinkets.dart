import 'dart:math';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';

import 'apps.dart';
import 'ui.dart';

/// Barra superior de trinkets (widgets propios). Agregá los tuyos acá.
class TrinketBar extends StatelessWidget {
  const TrinketBar({super.key});

  @override
  Widget build(BuildContext context) => const Row(
    children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [ClockTrinket(), SizedBox(width: 12), PowerButton()]),
      Spacer(),
      MoonTrinket(),
    ],
  );
}

/// Símbolo de encendido: círculo abierto arriba con una línea en el medio.
const powerGlyph = [
  '.....#.....',
  '..#..#..#..',
  '.#...#...#.',
  '#....#....#',
  '#....#....#',
  '#....#....#',
  '#.........#',
  '#.........#',
  '.#.......#.',
  '..#.....#..',
  '...#####...',
];

/// Botón de apagado: menú con apagar y reiniciar.
class PowerButton extends StatelessWidget {
  const PowerButton({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Apagar',
    child: PixelTile(
      label: '',
      leading: const PixelGlyph(powerGlyph, size: Px.icon * 0.75), // del alto del texto de los tiles
      onTap: () => showPixelMenu(context, 'APAGAR', [
        ('Apagar', () => power(context, 'shutdown')),
        ('Reiniciar', () => power(context, 'reboot')),
        ('Cancelar', () {}),
      ]),
    ),
  );
}

/// Apaga o reinicia ([action]: 'shutdown' o 'reboot'). Con root lo hace directo; si no, abre el menú
/// de apagado de Android (necesita el servicio de accesibilidad); si no está activado, ofrece activarlo.
Future<void> power(BuildContext context, String action) async {
  final how = await native.invokeMethod<String>('power', {'action': action});
  if (how != 'none' || !context.mounted) return;
  showPixelMenu(context, 'Sin root, Android no deja apagar directo. Activá "Pixel Launcher" en Accesibilidad', [
    ('Abrir Accesibilidad', () => const AndroidIntent(action: 'android.settings.ACCESSIBILITY_SETTINGS').launch()),
    ('Cancelar', () {}),
  ]);
}

final tick = Stream<void>.periodic(const Duration(seconds: 1)).asBroadcastStream();

String two(int v) => v.toString().padLeft(2, '0');

class ClockTrinket extends StatelessWidget {
  const ClockTrinket({super.key});

  @override
  Widget build(BuildContext context) => StreamBuilder(
    stream: tick,
    builder: (_, _) {
      final n = DateTime.now();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${two(n.hour)}:${two(n.minute)}', style: Px.big),
          Text('${two(n.day)}/${two(n.month)}/${n.year}', style: Px.text.copyWith(color: Px.dim)),
        ],
      );
    },
  );
}

const moonNames = [
  'NUEVA',
  'CRECIENTE',
  'CUARTO CRECIENTE',
  'GIBOSA CRECIENTE',
  'LLENA',
  'GIBOSA MENGUANTE',
  'CUARTO MENGUANTE',
  'MENGUANTE',
];

/// Fase lunar 0..7 (0 = nueva, 4 = llena), contando desde una luna nueva conocida.
int moonPhase(DateTime t) {
  const synodic = 29.530588853;
  final days = t.toUtc().difference(DateTime.utc(2000, 1, 6, 18, 14)).inMinutes / 1440;
  return ((days % synodic) / synodic * 8).round() % 8;
}

class MoonTrinket extends StatelessWidget {
  const MoonTrinket({super.key});

  @override
  Widget build(BuildContext context) {
    final phase = moonPhase(DateTime.now());
    return Semantics(
      label: 'Luna ${moonNames[phase].toLowerCase()}',
      child: PixelGlyph(moonGlyph(phase), size: Px.big.fontSize ?? 40),
    );
  }
}

/// Dibujo de la luna en la [phase] 0..7 para PixelGlyph ('#' iluminada, '+' en sombra), en una
/// grilla de [n]×[n]. Vista desde el hemisferio sur: la creciente se ilumina a la izquierda (como una C).
List<String> moonGlyph(int phase, {int n = 13}) {
  final t = phase / 8 * 2 * pi; // 0 = nueva, π = llena
  String px(int r, int c) {
    final x = (c + 0.5) / n * 2 - 1, y = (r + 0.5) / n * 2 - 1;
    if (x * x + y * y > 1) return '.';
    // la línea de sombra es media elipse de ancho cos(t)
    final edge = cos(t) * sqrt(1 - y * y);
    final lit = t <= pi ? -x > edge : x > edge;
    return lit ? '#' : '+';
  }

  return [
    for (var r = 0; r < n; r++) [for (var c = 0; c < n; c++) px(r, c)].join(),
  ];
}
