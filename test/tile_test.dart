import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_launcher/ui.dart';

void main() {
  testWidgets('PixelTile resalta lo que coincide, sin importar mayúsculas', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PixelTile(label: 'YouTube Music', match: 'mus'),
      ),
    );
    // Text.rich envuelve los spans en uno con el estilo: juntamos las hojas
    final spans = <TextSpan>[];
    tester.widget<RichText>(find.byType(RichText)).text.visitChildren((s) {
      if (s is TextSpan && s.children == null) spans.add(s);
      return true;
    });
    expect(spans.map((s) => s.text), ['YouTube ', 'Mus', 'ic']);
    expect(spans[1].style?.color, Px.accent);
  });

  testWidgets('PixelTile sin coincidencia muestra el label entero', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PixelTile(label: 'Chrome', match: 'zz'),
      ),
    );
    expect(find.text(' Chrome'), findsOneWidget);
  });
}
