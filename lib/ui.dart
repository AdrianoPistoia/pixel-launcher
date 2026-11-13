import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Estilos del launcher: pixel-art o G.U. (navy, líneas cian, acentos ámbar, paneles biselados).
enum PxStyle { pixel, gu }

/// Sistema de diseño. Cambiá estos valores para re-skinear todo el launcher; cada uno tiene su
/// versión pixel y G.U. según [style] (lo cambia `store.setStyle`).
class Px {
  static var style = PxStyle.pixel;
  static bool get gu => style == PxStyle.gu;

  static Color get bg => gu ? const Color(0xFF070B14) : const Color(0xFF14101E);
  static Color get fg => gu ? const Color(0xFFD6E8F5) : const Color(0xFFE8D9A8);
  static Color get accent => gu ? const Color(0xFFF0913A) : const Color(0xFF7BD389);
  static Color get dim => gu ? const Color(0xFF2E5A78) : const Color(0xFF6B5E7A); // bordes y decoración
  static Color get dimText => gu ? const Color(0xFF7FA3BD) : const Color(0xFF9C90AC); // texto secundario
  static Color get hi => gu ? const Color(0xFF39C7E8) : fg; // relleno de lo elegido
  static Color get userBubble => gu
      ? const Color(0xE6247A9E)
      : const Color(0xFF2F6F8F); // celeste apagado y casi opaco: el texto claro se sigue leyendo
  static const shadow = Color(0xFF000000);

  static String get font => gu ? 'SpaceGrotesk' : 'VT323';
  static const unit = 2.0; // tamaño de un "pixel" de borde/sombra
  static const icon = 32.0; // tamaño en pantalla de los íconos
  static int get iconRes => gu ? 96 : 16; // resolución real: menor = más pixelado
  static const photoRes = 128; // ancho real de las fotos pixeladas

  /// Tamaño de letra pensado para VT323, ajustado a la fuente del estilo (VT323 se ve más chica).
  static double sz(double vt) => gu ? vt * 0.72 : vt;

  /// Código (bloques del chat de Claude): VT323 ya es monoespaciada; Space Grotesk no.
  static TextStyle get code => text.copyWith(fontFamily: gu ? 'monospace' : font, fontSize: sz(18));

  static TextStyle get text => gu
      ? TextStyle(fontFamily: font, fontSize: 17, color: fg, height: 1.15, letterSpacing: 0.6)
      : TextStyle(fontFamily: font, fontSize: 24, color: fg, height: 1);
  static TextStyle get big => gu
      ? TextStyle(fontFamily: font, fontSize: 34, color: fg, height: 1, fontWeight: FontWeight.w300, letterSpacing: 2)
      : TextStyle(fontFamily: font, fontSize: 40, color: fg, height: 1);

  /// Borde de un panel: recto en pixel; en G.U. fino y con la esquina de abajo a la derecha biselada.
  static ShapeBorder border(Color color) => gu
      ? BeveledRectangleBorder(
          side: BorderSide(color: color, width: 1.5),
          borderRadius: const BorderRadius.only(bottomRight: Radius.circular(10)),
        )
      : RoundedRectangleBorder(
          side: BorderSide(color: color, width: unit * 2),
        );

  /// Caja: en pixel, bordes rectos y sombra dura sin blur; en G.U., panel translúcido que brilla al elegirlo.
  static ShapeDecoration box({bool active = false}) => ShapeDecoration(
    color: active ? hi : (gu ? bg.withValues(alpha: 0.8) : bg),
    shape: border(active ? hi : dim),
    shadows: gu
        ? [if (active) BoxShadow(color: hi.withValues(alpha: 0.45), blurRadius: 14)]
        : const [BoxShadow(color: shadow, offset: Offset(unit * 2, unit * 2))],
  );

  /// Cuadro de mensaje del usuario en el chat: caja con fondo celeste.
  static ShapeDecoration bubble({bool focused = false}) => ShapeDecoration(
    color: userBubble,
    shape: border(focused ? hi : userBubble),
    shadows: gu ? null : const [BoxShadow(color: shadow, offset: Offset(unit * 2, unit * 2))],
  );

  static InputDecoration input(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: text.copyWith(color: dim),
    isDense: true,
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: BorderSide(color: dim, width: unit * 2),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: BorderSide(color: hi, width: unit * 2),
    ),
  );

  static ThemeData theme() => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: bg,
    fontFamily: font,
    splashFactory: NoSplash.splashFactory,
    iconTheme: IconThemeData(color: fg),
    highlightColor: Colors.transparent,
    textSelectionTheme: TextSelectionThemeData(cursorColor: fg, selectionColor: dim),
  );
}

/// "Menú" del mando: hace lo mismo que mantener apretado. Lo dispara el botón del layout (`pad.dart`).
class MenuIntent extends Intent {
  const MenuIntent();
}

/// Elemento seleccionable: tap/long-press táctil y foco con D-pad/gamepad (confirmar = tap,
/// menú = long-press).
class PixelTile extends StatefulWidget {
  const PixelTile({
    super.key,
    required this.label,
    this.leading,
    this.onTap,
    this.onLongPress,
    this.onMenu,
    this.selected = false,
    this.autofocus = false,
    this.vertical = false,
    this.match = '',
    this.maxLines = 1,
  });

  final String label;
  final Widget? leading;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onMenu; // solo botón de menú del mando (el long-press táctil lo usa otro gesto, p. ej. arrastrar)
  final bool selected;
  final bool autofocus;
  final bool vertical; // ícono arriba y texto abajo, centrado (para grillas)
  final String match; // parte del label a resaltar (sin importar mayúsculas), p. ej. lo que se buscó
  final int? maxLines; // null = todas las que haga falta (mensajes largos)

  @override
  State<PixelTile> createState() => _PixelTileState();
}

class _PixelTileState extends State<PixelTile> {
  bool focused = false;

  @override
  Widget build(BuildContext context) {
    final on = focused || widget.selected;
    final name = widget.label;
    final at = widget.match.isEmpty ? -1 : name.toLowerCase().indexOf(widget.match.toLowerCase());
    final end = at + widget.match.length;
    final label = Text.rich(
      TextSpan(
        text: focused ? '>' : ' ',
        children: at < 0
            ? [TextSpan(text: name)]
            : [
                TextSpan(text: name.substring(0, at)),
                // con el tile invertido el verde no se lee: subrayado
                TextSpan(
                  text: name.substring(at, end),
                  style: on ? const TextStyle(decoration: TextDecoration.underline) : TextStyle(color: Px.accent),
                ),
                TextSpan(text: name.substring(end)),
              ],
      ),
      style: Px.text.copyWith(color: on ? Px.bg : Px.fg),
      maxLines: widget.maxLines,
      // ellipsis sin maxLines corta en la primera línea: con null, que haga todas las que necesite
      overflow: widget.maxLines == null ? TextOverflow.clip : TextOverflow.ellipsis,
    );
    return FocusableActionDetector(
      autofocus: widget.autofocus,
      onFocusChange: (f) => setState(() => focused = f),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onTap?.call()),
        if ((widget.onMenu ?? widget.onLongPress) != null)
          MenuIntent: CallbackAction<MenuIntent>(onInvoke: (_) => (widget.onMenu ?? widget.onLongPress)!()),
      },
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: Px.box(active: on),
          // los PixelGlyph toman este color: se invierten junto con el tile
          child: IconTheme(
            data: IconThemeData(color: on ? Px.bg : Px.fg),
            child: widget.vertical
                // el ícono ocupa lo que sobra de la celda, así nunca desborda
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (widget.leading != null) ...[
                        Expanded(child: FittedBox(child: widget.leading)),
                        const SizedBox(height: 8),
                      ],
                      label,
                    ],
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ?widget.leading,
                      // sin texto (solo ícono) el foco se ve por los colores invertidos
                      if (name.isNotEmpty) ...[
                        if (widget.leading != null) const SizedBox(width: 8),
                        Flexible(child: label),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Ícono de pixel-art dibujado con texto: '#' = pixel del color del IconTheme (se invierte dentro
/// de un PixelTile), '+' = pixel en sombra, cualquier otro = vacío.
class PixelGlyph extends StatelessWidget {
  const PixelGlyph(this.rows, {super.key, this.size = Px.icon});

  final List<String> rows;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _GlyphPainter(rows, IconTheme.of(context).color ?? Px.fg)),
  );
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.rows, this.color);

  final List<String> rows;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / rows.first.length;
    final on = Paint()
      ..color = color
      ..isAntiAlias = false;
    final shade = Paint()
      ..color = Px.dim
      ..isAntiAlias = false;
    for (final (y, row) in rows.indexed) {
      for (var x = 0; x < row.length; x++) {
        final paint = switch (row[x]) {
          '#' => on,
          '+' => shade,
          _ => null,
        };
        // bordes calculados por índice: celdas vecinas comparten borde exacto, sin rendijas
        if (paint != null) {
          canvas.drawRect(Rect.fromLTRB(x * cell, y * cell, (x + 1) * cell, (y + 1) * cell), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => old.color != color || old.rows != rows;
}

/// Ícono pixelado: se decodifica a [Px.iconRes] px y se escala sin suavizado.
class PixelIcon extends StatelessWidget {
  const PixelIcon(this.bytes, {super.key});

  final Uint8List? bytes;

  @override
  Widget build(BuildContext context) => bytes == null
      ? const SizedBox.square(dimension: Px.icon)
      : Image.memory(
          bytes!,
          width: Px.icon,
          height: Px.icon,
          cacheWidth: Px.iconRes,
          filterQuality: Px.gu ? FilterQuality.medium : FilterQuality.none,
          gaplessPlayback: true,
        );
}

/// Diálogo con borde pixel: título y contenido.
Future<T?> showPixelDialog<T>(BuildContext context, String title, Widget Function(BuildContext ctx) body) =>
    showDialog<T>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Px.bg,
        shape: Px.border(Px.hi),
        child: SingleChildScrollView(
          // con el teclado abierto en horizontal queda muy poco alto
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Px.text.copyWith(color: Px.accent)),
              const SizedBox(height: 8),
              body(ctx),
            ],
          ),
        ),
      ),
    );

/// Menú de opciones: cada una cierra el diálogo y ejecuta su acción. El foco arranca en la primera.
void showPixelMenu(BuildContext context, String title, List<(String, VoidCallback)> options) => showPixelDialog(
  context,
  title,
  (ctx) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (i, (label, action)) in options.indexed)
        Padding(
          padding: EdgeInsets.only(top: i > 0 ? 4 : 0),
          child: PixelTile(
            autofocus: i == 0,
            label: label,
            onTap: () {
              Navigator.pop(ctx);
              action();
            },
          ),
        ),
    ],
  ),
);

/// Pide un texto; null si se cancela.
Future<String?> askText(BuildContext context, String title, {String hint = '', String initial = ''}) {
  final input = TextEditingController(text: initial);
  return showPixelDialog<String>(
    context,
    title,
    (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: input,
          autofocus: true,
          style: Px.text,
          decoration: Px.input(hint),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        const SizedBox(height: 8),
        PixelTile(label: 'OK', onTap: () => Navigator.pop(ctx, input.text)),
      ],
    ),
  );
}
