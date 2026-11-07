import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_launcher/trinkets.dart';

void main() {
  test('fase lunar en fechas conocidas', () {
    expect(moonPhase(DateTime.utc(2024, 4, 8, 18, 21)), 0); // luna nueva (eclipse)
    expect(moonPhase(DateTime.utc(2024, 4, 23, 23, 49)), 4); // luna llena
    expect(moonPhase(DateTime.utc(2024, 4, 15, 19, 13)), 2); // cuarto creciente
  });

  test('dibujo de la luna (hemisferio sur)', () {
    String middle(int phase) => moonGlyph(phase)[6]; // fila del medio, 13 de ancho
    expect(moonGlyph(0).join().contains('#'), isFalse); // nueva: toda en sombra
    expect(moonGlyph(4).join().contains('+'), isFalse); // llena: toda iluminada
    expect(middle(2).startsWith('######'), isTrue); // cuarto creciente: izquierda iluminada
    expect(middle(2).endsWith('++++++'), isTrue);
    expect(middle(6).startsWith('++++++'), isTrue); // cuarto menguante: derecha iluminada
    expect(middle(6).endsWith('######'), isTrue);
  });
}
