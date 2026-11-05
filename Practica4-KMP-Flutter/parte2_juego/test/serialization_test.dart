import 'package:flutter_test/flutter_test.dart';
import 'package:juego_partidas/model.dart';

void main() {
  GameState sample() => GameState.newGame(levels[1])
    ..name = 'Prueba'
    ..tag = 'Récord'
    ..score = 123
    ..elapsedSeconds = 45
    ..moves.addAll([0, 6, 12]);

  for (final f in SaveFormat.values) {
    test('ida y vuelta ${f.name}', () {
      final g = sample();
      final r = GameState.parse(g.serialize(f), f.name);
      expect(r.id, g.id);
      expect(r.board, g.board);
      expect(r.moves, g.moves);
      expect(r.score, 123);
      expect(r.elapsedSeconds, 45);
      expect(r.tag, 'Récord');
      expect(r.levelId, 2);
    });
    test('vacío ${f.name}', () {
      expect(() => GameState.parse('', f.name), throwsA(isA<SaveFormatError>()));
    });
    test('truncado ${f.name}', () {
      final s = sample().serialize(f);
      expect(() => GameState.parse(s.substring(0, s.length ~/ 2), f.name), throwsA(isA<SaveFormatError>()));
    });
  }

  test('el tablero nuevo tiene solución (deshacer toques)', () {
    final g = GameState.newGame(levels[0]);
    expect(g.solved, false);
  });
}
