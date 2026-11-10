import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:installed_apps/app_info.dart';

import 'apps.dart';
import 'pad.dart';
import 'pages.dart';
import 'tabs.dart';
import 'ui.dart';
import 'utilities.dart';

// Piezas del estilo G.U.: panal de fondo, anillo de canales y espada del menú SYS.
// Dibujadas a mano: nada de arte, logos ni nombres del juego.

/// Fondo de panal con un lavado cian desde arriba a la izquierda.
class HexBackdrop extends StatelessWidget {
  const HexBackdrop({super.key});

  @override
  Widget build(BuildContext context) => RepaintBoundary(child: CustomPaint(painter: _HexPainter(Px.dim, Px.hi)));
}

class _HexPainter extends CustomPainter {
  _HexPainter(this.line, this.wash);

  final Color line, wash;
  static const r = 16.0; // radio de cada hexágono

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.topLeft,
          radius: 1.2,
          colors: [wash.withValues(alpha: 0.10), wash.withValues(alpha: 0)],
        ).createShader(rect),
    );
    // hexágonos de punta plana, columnas desfasadas media altura
    final h = sqrt(3) * r, path = Path();
    for (var col = 0; col * r * 1.5 < size.width + r; col++) {
      for (var row = -1; row * h < size.height + h; row++) {
        final c = Offset(col * r * 1.5, row * h + (col.isOdd ? h / 2 : 0));
        path.addPolygon([for (var k = 0; k < 6; k++) c + Offset(cos(k * pi / 3), sin(k * pi / 3)) * r], true);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = line.withValues(alpha: 0.22),
    );
  }

  @override
  bool shouldRepaint(_HexPainter old) => old.line != line || old.wash != wash;
}

// ─── Anillo ──────────────────────────────────────────────────────────────────

/// Anillo: los canales elegidos (en la config de la pestaña, 'apps') en una órbita inclinada.
/// Sin elegir: hasta 8, las fijadas y después las más usadas.
/// El de adelante se abre; flechas, swipe o tocar otro lo hacen girar.
class RingPage extends StatefulWidget {
  const RingPage(this.tab, {super.key});

  final int tab;

  @override
  State<RingPage> createState() => _RingPageState();
}

class _RingPageState extends State<RingPage> {
  static const tilt = -14 * pi / 180; // inclinación del plano del anillo
  static const channels = 8;

  int sel = 0; // sin módulo: así gira siempre por el camino corto
  double drag = 0;

  List<AppInfo> get apps {
    final chosen = tabStore.tabs[widget.tab]['apps'] as List?;
    if (chosen != null) return [for (final p in chosen) ...store.apps.where((a) => a.packageName == p)];
    final pinned = store.pinnedApps;
    return [...pinned, ...store.byUse.where((a) => !pinned.contains(a))].take(channels).toList();
  }

  /// Elegir los canales, partiendo de los que se ven ahora.
  Future<void> pick() async {
    final picked = await pickApps(context, [for (final a in apps) a.packageName]);
    if (picked == null) return;
    tabStore.tabs[widget.tab]['apps'] = picked;
    await tabStore.save();
  }

  void menu(AppInfo app) => showPixelMenu(context, app.name, [
    ('Elegir canales', pick),
    ('Opciones de la app', () => showAppMenu(context, app)),
  ]);

  void spin(int d) => setState(() => sel += d);

  /// Gira hasta el canal [k] por el lado más corto.
  void spinTo(int k, int n) {
    var d = (k - sel) % n;
    if (d > n / 2) d -= n;
    spin(d);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([store, tabStore]),
    builder: (context, _) {
      final apps = this.apps;
      if (apps.isEmpty) {
        return Center(
          child: PixelTile(autofocus: true, label: '+ CANALES', onTap: pick),
        );
      }
      final n = apps.length, i = sel % n, app = apps[i];
      return Focus(
        autofocus: true,
        onKeyEvent: (node, e) {
          if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
          final k = e.logicalKey;
          if (k == LogicalKeyboardKey.arrowLeft) {
            spin(-1);
          } else if (k == LogicalKeyboardKey.arrowRight) {
            spin(1);
          } else if (isOk(k)) {
            store.launch(app.packageName);
          } else if (k == padKey(PadButton.menu)) {
            menu(app);
          } else {
            return KeyEventResult.ignored;
          }
          return KeyEventResult.handled;
        },
        // en horizontal el panel va al costado: el alto es lo que le falta al anillo
        child: LayoutBuilder(
          builder: (context, box) {
            final wide = box.maxWidth > box.maxHeight * 1.3;
            return Flex(
              direction: wide ? Axis.horizontal : Axis.vertical,
              crossAxisAlignment: wide ? CrossAxisAlignment.center : CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _spinner(apps)),
                const SizedBox.square(dimension: 12),
                wide ? SizedBox(width: box.maxWidth * 0.36, child: _panel(app, i, n)) : _panel(app, i, n),
              ],
            );
          },
        ),
      );
    },
  );

  /// El anillo animado. El swipe sobre él lo gira; para cambiar de pestaña queda la barra (o L1/R1).
  Widget _spinner(List<AppInfo> apps) => GestureDetector(
    onHorizontalDragUpdate: (d) {
      drag += d.delta.dx;
      if (drag.abs() > 40) {
        spin(-drag.sign.toInt());
        drag = 0;
      }
    },
    onHorizontalDragEnd: (_) => drag = 0,
    child: LayoutBuilder(
      builder: (context, box) => TweenAnimationBuilder<double>(
        tween: Tween(end: sel.toDouble()),
        duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        builder: (context, pos, _) => _ring(box.biggest, apps, pos),
      ),
    ),
  );

  Widget _ring(Size size, List<AppInfo> apps, double pos) {
    final n = apps.length;
    final c = Offset(size.width / 2, size.height * 0.46);
    // lo que entre a lo ancho o a lo alto: la elipse inclinada más el canal de adelante abajo
    final rx = min(size.width * 0.42, size.height * 0.48), ry = rx * 0.64;
    final plate = rx * 0.57; // tamaño del canal de adelante
    // posición en la elipse para un ángulo, con el plano ya inclinado; 0 = adelante (abajo)
    Offset at(double t) {
      final x = rx * sin(t), y = ry * cos(t);
      return c + Offset(x * cos(tilt) - y * sin(tilt), x * sin(tilt) + y * cos(tilt));
    }

    final order = [for (var k = 0; k < n; k++) (k: k, t: (k - pos) * 2 * pi / n)]
      ..sort((a, b) => cos(a.t).compareTo(cos(b.t))); // los de atrás se dibujan primero
    final front = at(0);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: CustomPaint(painter: _OrbitPainter(c, rx, ry, tilt, Px.hi))),
        Align(
          alignment: const Alignment(0, -0.15),
          child: Text(
            '${(sel % n + 1).toString().padLeft(2, '0')} / ${n.toString().padLeft(2, '0')}',
            style: Px.big.copyWith(color: Px.dim),
          ),
        ),
        // retícula fija adelante: el canal elegido entra en ella
        Positioned(
          left: front.dx - plate * 0.8,
          top: front.dy - plate * 0.8,
          child: _Diamond(size: plate * 1.6, line: Px.accent.withValues(alpha: 0.6)),
        ),
        for (final (:k, :t) in order) _plate(apps[k], at(t), (cos(t) + 1) / 2, plate, () => spinTo(k, n)),
      ],
    );
  }

  /// Un canal: rombo con el ícono derecho. Más chico y transparente cuanto más atrás ([depth] 0..1).
  Widget _plate(AppInfo app, Offset p, double depth, double plate, VoidCallback select) {
    final s = plate * (0.35 + 0.65 * pow(depth, 1.5));
    final front = depth > 0.98;
    return Positioned(
      left: p.dx - s / 2,
      top: p.dy - s / 2,
      child: Opacity(
        opacity: 0.15 + 0.85 * pow(depth, 1.8),
        child: GestureDetector(
          onTap: front ? () => store.launch(app.packageName) : select,
          onLongPress: () => menu(app),
          child: _Diamond(
            size: s,
            line: front ? Px.hi : Px.dim,
            fill: Px.bg,
            glow: front,
            child: SizedBox.square(
              dimension: s * 0.42,
              child: FittedBox(child: PixelIcon(app.icon)),
            ),
          ),
        ),
      ),
    );
  }

  /// Panel ancho y bajo: nombre a la izquierda, canal a la derecha, línea de detalle en mono.
  Widget _panel(AppInfo app, int i, int n) {
    final mono = TextStyle(fontFamily: 'PlexMono', fontSize: 11, color: Px.dimText, letterSpacing: 1);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: Px.box(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  app.name,
                  style: Px.text.copyWith(color: Px.hi),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text('CANAL ${i + 1}/$n', style: mono.copyWith(color: Px.accent)),
            ],
          ),
          Container(height: 1, margin: const EdgeInsets.symmetric(vertical: 6), color: Px.dim),
          Text(
            '${app.packageName} · ${store.uses(app.packageName)} aperturas',
            style: mono,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            '${padLabel(PadButton.ok)} ABRIR · ← → GIRAR · ${padLabel(PadButton.menu)} OPCIONES',
            style: mono,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Rombo (cuadrado a 45°) de lado tal que entra justo en [size]; [child] queda derecho.
class _Diamond extends StatelessWidget {
  const _Diamond({required this.size, required this.line, this.fill, this.glow = false, this.child});

  final double size;
  final Color line;
  final Color? fill;
  final bool glow;
  final Widget? child;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Transform.rotate(
          angle: pi / 4,
          child: Container(
            width: size / sqrt2,
            height: size / sqrt2,
            decoration: BoxDecoration(
              color: fill,
              border: Border.all(color: line, width: 1.5),
              boxShadow: glow ? [BoxShadow(color: line.withValues(alpha: 0.5), blurRadius: 14)] : null,
            ),
          ),
        ),
        ?child,
      ],
    ),
  );
}

/// La órbita: elipse inclinada con brillo y puntos que se apagan hacia atrás.
class _OrbitPainter extends CustomPainter {
  _OrbitPainter(this.c, this.rx, this.ry, this.tilt, this.color);

  final Offset c;
  final double rx, ry, tilt;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..translate(c.dx, c.dy)
      ..rotate(tilt);
    final oval = Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2);
    final line = Paint()..style = PaintingStyle.stroke;
    canvas
      ..drawOval(
        oval,
        line
          ..strokeWidth = 8
          ..color = color.withValues(alpha: 0.12)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      )
      ..drawOval(
        oval,
        line
          ..strokeWidth = 1
          ..color = color.withValues(alpha: 0.45)
          ..maskFilter = null,
      )
      ..drawOval(oval.deflate(rx * 0.25), line..color = color.withValues(alpha: 0.12));
    final dot = Paint();
    for (var k = 0; k < 84; k++) {
      final t = k / 84 * 2 * pi, depth = (cos(t) + 1) / 2;
      canvas.drawCircle(
        Offset(rx * sin(t), ry * cos(t)) * 1.08,
        1.4,
        dot..color = color.withValues(alpha: 0.08 + 0.4 * depth),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OrbitPainter old) =>
      old.c != c || old.rx != rx || old.ry != ry || old.tilt != tilt || old.color != color;
}

// ─── Espada del menú SYS ─────────────────────────────────────────────────────

/// Espada grande en diagonal detrás del menú: hoja con dientes de sierra y una cadena en el
/// canal, guarda en ámbar y anillos de mira alrededor. Diseño propio.
class SwordBackdrop extends StatelessWidget {
  const SwordBackdrop({super.key});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(child: CustomPaint(painter: _SwordPainter(Px.hi, Px.accent, Px.bg))),
  );
}

class _SwordPainter extends CustomPainter {
  _SwordPainter(this.line, this.accent, this.bg);

  final Color line, accent, bg;

  @override
  void paint(Canvas canvas, Size size) {
    // de la empuñadura (abajo a la izquierda) a la punta (arriba a la derecha); se dibuja sobre el eje x
    final a = Offset(size.width * 0.06, size.height * 0.97), b = Offset(size.width * 0.9, size.height * 0.03);
    final l = (b - a).distance, w = l * 0.12; // largo y ancho de la hoja
    canvas
      ..save()
      ..translate(a.dx, a.dy)
      ..rotate((b - a).direction);
    Paint stroke(Color c, double width, [double alpha = 1]) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = c.withValues(alpha: alpha);

    // anillos de mira alrededor de la guarda
    final guard = Offset(l * 0.19, 0);
    canvas
      ..drawCircle(guard, l * 0.16, stroke(line, 1, 0.18))
      ..drawCircle(guard, l * 0.2, stroke(line, 1, 0.08));

    // hoja: lomo recto, punta en ángulo y filo de sierra con los dientes hacia la punta
    final x0 = l * 0.21, tooth = l * 0.03;
    final blade = Path()
      ..moveTo(x0, -w / 2)
      ..lineTo(l * 0.86, -w / 2)
      ..lineTo(l, 0)
      ..lineTo(l * 0.9, w / 2);
    for (var x = l * 0.9; x > x0 + tooth; x -= tooth) {
      blade
        ..lineTo(x - tooth * 0.7, w / 2 + tooth * 0.45)
        ..lineTo(x - tooth, w / 2);
    }
    blade
      ..lineTo(x0, w / 2)
      ..close();
    canvas
      ..drawPath(
        blade,
        Paint()
          ..shader = LinearGradient(
            colors: [line.withValues(alpha: 0.16), line.withValues(alpha: 0.03)],
          ).createShader(Rect.fromLTRB(x0, -w, l, w)),
      )
      ..drawPath(blade, stroke(line, 7, 0.10)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5))
      ..drawPath(blade, stroke(line, 1.4, 0.55));

    // la cadena por el canal: eslabones alternados (de frente y de canto)
    final link = l * 0.036;
    for (var k = 0; l * 0.25 + k * link * 1.15 < l * 0.82; k++) {
      final x = l * 0.25 + k * link * 1.15;
      final r = k.isEven
          ? Rect.fromCenter(center: Offset(x, 0), width: link * 1.3, height: w * 0.32)
          : Rect.fromCenter(center: Offset(x, 0), width: link * 1.3, height: w * 0.08);
      canvas.drawRect(r, stroke(line, 1.2, 0.5));
    }

    // guarda angulosa en ámbar
    final g = Path()
      ..moveTo(l * 0.17, -w * 0.3)
      ..lineTo(l * 0.185, -w * 1.05)
      ..lineTo(l * 0.215, -w * 0.95)
      ..lineTo(l * 0.21, -w * 0.3)
      ..lineTo(l * 0.21, w * 0.3)
      ..lineTo(l * 0.215, w * 0.95)
      ..lineTo(l * 0.185, w * 1.05)
      ..lineTo(l * 0.17, w * 0.3)
      ..close();
    canvas
      ..drawPath(g, Paint()..color = bg.withValues(alpha: 0.85))
      ..drawPath(g, stroke(accent, 1.5, 0.8));

    // empuñadura con vendas y pomo en rombo
    final grip = Rect.fromLTRB(l * 0.05, -w * 0.16, l * 0.17, w * 0.16);
    canvas.drawRect(grip, stroke(line, 1.2, 0.5));
    for (var x = grip.left + l * 0.012; x < grip.right; x += l * 0.014) {
      canvas.drawLine(Offset(x, grip.top), Offset(x - l * 0.008, grip.bottom), stroke(line, 1, 0.3));
    }
    final pommel = Path()
      ..moveTo(0, 0)
      ..lineTo(l * 0.025, -w * 0.25)
      ..lineTo(l * 0.05, 0)
      ..lineTo(l * 0.025, w * 0.25)
      ..close();
    canvas
      ..drawPath(pommel, stroke(accent, 1.5, 0.8))
      ..restore();
  }

  @override
  bool shouldRepaint(_SwordPainter old) => old.line != line || old.accent != accent || old.bg != bg;
}
