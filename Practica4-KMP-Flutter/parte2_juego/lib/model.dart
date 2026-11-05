import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';
import 'theme.dart';

/// Juego original "Apagón": tablero de luces; tocar una celda invierte ella y
/// sus 4 vecinos. El jugador debe apagar todas. Modos: 3x3 (Nivel 1) y 5x5 (Nivel 2).
enum SaveFormat { txt, xml, json }

class Level {
  final int id, size, shuffleTaps;
  final String name;
  const Level(this.id, this.name, this.size, this.shuffleTaps);
}

const levels = [
  Level(1, 'Nivel 1 · Chispa (3x3)', 3, 5),
  Level(2, 'Nivel 2 · Tormenta (5x5)', 5, 12),
];

class SaveFormatError implements Exception {
  final String message;
  SaveFormatError(this.message);
  @override
  String toString() => message;
}

class GameState {
  String id;
  String name;
  String tag; // etiqueta / categoría de la partida
  int levelId;
  List<bool> board; // true = encendida
  int score;
  int elapsedSeconds;
  List<int> moves; // historial de movimientos (índices tocados)
  bool sound, haptics, showCounter; // configuraciones personalizadas
  String palette;
  DateTime savedAt;

  GameState({
    required this.id,
    this.name = 'Partida',
    this.tag = 'General',
    required this.levelId,
    required this.board,
    this.score = 0,
    this.elapsedSeconds = 0,
    List<int>? moves,
    this.sound = true,
    this.haptics = true,
    this.showCounter = true,
    this.palette = 'guinda',
    DateTime? savedAt,
  })  : moves = moves ?? [],
        savedAt = savedAt ?? DateTime.now();

  Level get level => levels.firstWhere((l) => l.id == levelId, orElse: () => levels[0]);
  int get size => level.size;
  bool get solved => board.isNotEmpty && !board.contains(true);

  factory GameState.newGame(Level l, {String palette = 'guinda', bool sound = true, bool haptics = true}) {
    final r = Random();
    final b = List<bool>.filled(l.size * l.size, false);
    // Se parte de un tablero resuelto y se aplican toques aleatorios => siempre tiene solución.
    var g = GameState(id: DateTime.now().millisecondsSinceEpoch.toString(), levelId: l.id, board: b, palette: palette, sound: sound, haptics: haptics);
    final used = <int>{};
    while (used.length < l.shuffleTaps) {
      used.add(r.nextInt(b.length));
    }
    for (final i in used) {
      g.toggle(i);
    }
    if (g.solved) g.toggle(0);
    g.moves.clear();
    return g;
  }

  void toggle(int i) {
    final n = size;
    final x = i % n, y = i ~/ n;
    void f(int xx, int yy) {
      if (xx >= 0 && xx < n && yy >= 0 && yy < n) board[yy * n + xx] = !board[yy * n + xx];
    }

    f(x, y);
    f(x + 1, y);
    f(x - 1, y);
    f(x, y + 1);
    f(x, y - 1);
    moves.add(i);
  }

  /// Puntuación: base por nivel menos penalización por movimientos y tiempo.
  int computeScore() => max(0, level.size * 400 - moves.length * 10 - elapsedSeconds);

  // ---------------- Serialización ----------------
  Map<String, dynamic> toMap() => {
        'game': 'Apagon',
        'version': 1,
        'id': id,
        'name': name,
        'tag': tag,
        'level': levelId,
        'board': board.map((e) => e ? 1 : 0).join(),
        'score': score,
        'elapsedSeconds': elapsedSeconds,
        'moves': moves,
        'settings': {'sound': sound, 'haptics': haptics, 'showCounter': showCounter, 'palette': palette},
        'savedAt': savedAt.toIso8601String(),
      };

  static GameState fromMap(Map m) {
    try {
      if (m['game'] != 'Apagon') throw SaveFormatError('El archivo no es una partida de Apagón.');
      final lvl = int.parse('${m['level']}');
      final level = levels.firstWhere((l) => l.id == lvl, orElse: () => throw SaveFormatError('Nivel desconocido: $lvl'));
      final bs = '${m['board']}';
      if (bs.length != level.size * level.size || bs.contains(RegExp(r'[^01]'))) {
        throw SaveFormatError('El tablero está incompleto o dañado.');
      }
      final s = (m['settings'] ?? {}) as Map;
      final moves = (m['moves'] as List).map((e) => int.parse('$e')).toList();
      if (moves.any((e) => e < 0 || e >= bs.length)) throw SaveFormatError('Historial de movimientos inválido.');
      return GameState(
        id: '${m['id']}',
        name: '${m['name']}',
        tag: '${m['tag']}',
        levelId: lvl,
        board: bs.split('').map((e) => e == '1').toList(),
        score: int.parse('${m['score']}'),
        elapsedSeconds: int.parse('${m['elapsedSeconds']}'),
        moves: moves,
        sound: '${s['sound']}' == 'true',
        haptics: '${s['haptics']}' == 'true',
        showCounter: '${s['showCounter']}' != 'false',
        palette: '${s['palette'] ?? 'guinda'}',
        savedAt: DateTime.parse('${m['savedAt']}'),
      );
    } on SaveFormatError {
      rethrow;
    } catch (e) {
      throw SaveFormatError('Faltan campos o hay valores inválidos en la partida.');
    }
  }

  String toJson() => const JsonEncoder.withIndent('  ').convert(toMap());

  static GameState fromJson(String s) {
    if (s.trim().isEmpty) throw SaveFormatError('El archivo está vacío.');
    try {
      final d = jsonDecode(s);
      if (d is! Map) throw SaveFormatError('El JSON no tiene la estructura esperada.');
      return fromMap(d);
    } on FormatException {
      throw SaveFormatError('JSON incompleto o corrupto.');
    }
  }

  /// Texto plano: líneas "clave=valor"; encabezado obligatorio.
  String toTxt() {
    final b = StringBuffer('APAGON-SAVE v1\n');
    final m = toMap();
    for (final k in ['id', 'name', 'tag', 'level', 'board', 'score', 'elapsedSeconds', 'savedAt']) {
      b.writeln('$k=${m[k]}');
    }
    b.writeln('moves=${moves.join(',')}');
    b.writeln('sound=$sound');
    b.writeln('haptics=$haptics');
    b.writeln('showCounter=$showCounter');
    b.writeln('palette=$palette');
    b.writeln('END');
    return b.toString();
  }

  static GameState fromTxt(String s) {
    if (s.trim().isEmpty) throw SaveFormatError('El archivo está vacío.');
    final lines = const LineSplitter().convert(s);
    if (lines.first.trim() != 'APAGON-SAVE v1') throw SaveFormatError('Encabezado TXT no reconocido.');
    if (lines.last.trim() != 'END') throw SaveFormatError('Archivo TXT incompleto (falta la línea END).');
    final kv = <String, String>{};
    for (final l in lines.skip(1)) {
      final i = l.indexOf('=');
      if (i > 0) kv[l.substring(0, i)] = l.substring(i + 1);
    }
    return fromMap({
      'game': 'Apagon',
      ...kv,
      'moves': (kv['moves'] ?? '').isEmpty ? [] : kv['moves']!.split(','),
      'settings': {'sound': kv['sound'], 'haptics': kv['haptics'], 'showCounter': kv['showCounter'], 'palette': kv['palette']},
    });
  }

  String toXml() {
    final b = XmlBuilder();
    b.processing('xml', 'version="1.0" encoding="UTF-8"');
    b.element('partida', attributes: {'juego': 'Apagon', 'version': '1'}, nest: () {
      for (final k in ['id', 'name', 'tag', 'level', 'board', 'score', 'elapsedSeconds', 'savedAt']) {
        b.element(k, nest: '${toMap()[k]}');
      }
      b.element('settings', nest: () {
        b.element('sound', nest: '$sound');
        b.element('haptics', nest: '$haptics');
        b.element('showCounter', nest: '$showCounter');
        b.element('palette', nest: palette);
      });
      b.element('moves', nest: () {
        for (final m in moves) {
          b.element('m', nest: '$m');
        }
      });
    });
    return b.buildDocument().toXmlString(pretty: true, indent: '  ');
  }

  static GameState fromXml(String s) {
    if (s.trim().isEmpty) throw SaveFormatError('El archivo está vacío.');
    try {
      final root = XmlDocument.parse(s).rootElement;
      if (root.name.local != 'partida') throw SaveFormatError('XML no es una partida.');
      String t(XmlElement e, String n) => e.getElement(n)?.innerText ?? (throw SaveFormatError('Falta el campo <$n>.'));
      final st = root.getElement('settings');
      return fromMap({
        'game': root.getAttribute('juego'),
        'id': t(root, 'id'),
        'name': t(root, 'name'),
        'tag': t(root, 'tag'),
        'level': t(root, 'level'),
        'board': t(root, 'board'),
        'score': t(root, 'score'),
        'elapsedSeconds': t(root, 'elapsedSeconds'),
        'savedAt': t(root, 'savedAt'),
        'moves': root.getElement('moves')?.findElements('m').map((e) => e.innerText).toList() ?? [],
        'settings': {
          'sound': st?.getElement('sound')?.innerText,
          'haptics': st?.getElement('haptics')?.innerText,
          'showCounter': st?.getElement('showCounter')?.innerText,
          'palette': st?.getElement('palette')?.innerText,
        },
      });
    } on XmlException {
      throw SaveFormatError('XML mal formado o incompleto.');
    }
  }

  String serialize(SaveFormat f) => switch (f) { SaveFormat.txt => toTxt(), SaveFormat.xml => toXml(), SaveFormat.json => toJson() };

  static GameState parse(String content, String ext) => switch (ext) {
        'txt' => fromTxt(content),
        'xml' => fromXml(content),
        'json' => fromJson(content),
        _ => throw SaveFormatError('Extensión no soportada: .$ext'),
      };
}

/// Entrada de la lista de partidas (puede ser válida o estar corrupta).
class SaveEntry {
  final File file;
  final GameState? state;
  final String? error;
  final int bytes;
  final DateTime modified;
  SaveEntry(this.file, this.state, this.error, this.bytes, this.modified);
  String get ext => file.path.split('.').last.toLowerCase();
  String get fileName => file.path.split(RegExp(r'[\\/]')).last;
}

/// Capa de persistencia: archivos en el almacenamiento PRIVADO de la app
/// (Documents en iOS / filesDir en Android) + SharedPreferences para opciones.
class Store extends ChangeNotifier {
  late SharedPreferences _p;
  late Directory dir;
  SaveFormat format = SaveFormat.json;
  AppPalette palette = AppPalette.guinda;
  bool sound = true, haptics = true, showCounter = true;
  int unlockedLevel = 1;
  int totalScore = 0;
  int gamesWon = 0;

  Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    final docs = await getApplicationDocumentsDirectory();
    dir = Directory('${docs.path}/partidas');
    await dir.create(recursive: true);
    format = SaveFormat.values.firstWhere((e) => e.name == _p.getString('format'), orElse: () => SaveFormat.json);
    palette = AppPalette.values.firstWhere((e) => e.name == _p.getString('palette'), orElse: () => AppPalette.guinda);
    sound = _p.getBool('sound') ?? true;
    haptics = _p.getBool('haptics') ?? true;
    showCounter = _p.getBool('counter') ?? true;
    unlockedLevel = _p.getInt('unlocked') ?? 1;
    totalScore = _p.getInt('total') ?? 0;
    gamesWon = _p.getInt('won') ?? 0;
  }

  Future<void> setOpt({SaveFormat? f, AppPalette? p, bool? s, bool? h, bool? c}) async {
    if (f != null) { format = f; await _p.setString('format', f.name); }
    if (p != null) { palette = p; await _p.setString('palette', p.name); }
    if (s != null) { sound = s; await _p.setBool('sound', s); }
    if (h != null) { haptics = h; await _p.setBool('haptics', h); }
    if (c != null) { showCounter = c; await _p.setBool('counter', c); }
    notifyListeners();
  }

  Future<void> registerWin(GameState g) async {
    gamesWon++;
    totalScore += g.score;
    if (g.levelId >= unlockedLevel && g.levelId < levels.length) unlockedLevel = g.levelId + 1;
    await _p.setInt('unlocked', unlockedLevel);
    await _p.setInt('total', totalScore);
    await _p.setInt('won', gamesWon);
    notifyListeners();
  }

  File fileFor(String id, SaveFormat f) => File('${dir.path}/partida_$id.${f.name}');

  /// Escritura atómica: se escribe a .tmp y luego se renombra, así un cierre
  /// inesperado no deja un archivo a medias.
  Future<File> save(GameState g, {SaveFormat? as}) async {
    final f = as ?? format;
    g.savedAt = DateTime.now();
    final target = fileFor(g.id, f);
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsString(g.serialize(f), flush: true);
    await tmp.rename(target.path);
    // Evita duplicados de la misma partida en otros formatos
    for (final other in SaveFormat.values) {
      if (other != f) {
        final o = fileFor(g.id, other);
        if (await o.exists()) await o.delete();
      }
    }
    notifyListeners();
    return target;
  }

  Future<List<SaveEntry>> list() async {
    final out = <SaveEntry>[];
    if (!await dir.exists()) return out;
    await for (final e in dir.list()) {
      if (e is! File) continue;
      final ext = e.path.split('.').last.toLowerCase();
      if (!['txt', 'xml', 'json'].contains(ext)) continue;
      final st = await e.stat();
      try {
        final g = GameState.parse(await e.readAsString(), ext);
        out.add(SaveEntry(e, g, null, st.size, st.modified));
      } on SaveFormatError catch (err) {
        out.add(SaveEntry(e, null, err.message, st.size, st.modified));
      } catch (err) {
        out.add(SaveEntry(e, null, 'No se pudo leer el archivo.', st.size, st.modified));
      }
    }
    out.sort((a, b) => b.modified.compareTo(a.modified));
    return out;
  }

  Future<GameState?> latest() async {
    for (final e in await list()) {
      if (e.state != null && !e.state!.solved) return e.state;
    }
    return null;
  }
}
