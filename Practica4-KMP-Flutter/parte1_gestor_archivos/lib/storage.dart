import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme.dart';

/// Persistencia ligera (SharedPreferences = SharedPreferences en Android y
/// NSUserDefaults en iOS): tema, recientes, favoritos y raíces autorizadas.
class Prefs extends ChangeNotifier {
  late SharedPreferences _p;
  AppPalette palette = AppPalette.guinda;
  List<String> recents = [];
  List<String> favorites = [];
  List<String> authorizedRoots = []; // carpetas elegidas con el selector

  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    palette = AppPalette.values.firstWhere(
        (e) => e.name == _p.getString('palette'),
        orElse: () => AppPalette.guinda);
    recents = _p.getStringList('recents') ?? [];
    favorites = _p.getStringList('favorites') ?? [];
    authorizedRoots = _p.getStringList('roots') ?? [];
  }

  Future<void> setPalette(AppPalette v) async {
    palette = v;
    await _p.setString('palette', v.name);
    notifyListeners();
  }

  Future<void> addRecent(String path) async {
    recents.remove(path);
    recents.insert(0, path);
    if (recents.length > 30) recents = recents.sublist(0, 30);
    await _p.setStringList('recents', recents);
    notifyListeners();
  }

  Future<void> clearRecents() async {
    recents = [];
    await _p.setStringList('recents', recents);
    notifyListeners();
  }

  bool isFav(String path) => favorites.contains(path);

  Future<void> toggleFav(String path) async {
    isFav(path) ? favorites.remove(path) : favorites.add(path);
    await _p.setStringList('favorites', favorites);
    notifyListeners();
  }

  /// Actualiza referencias cuando un archivo se mueve/renombra/elimina.
  Future<void> replacePath(String from, String? to) async {
    void fix(List<String> l) {
      final i = l.indexOf(from);
      if (i >= 0) to == null ? l.removeAt(i) : l[i] = to;
    }

    fix(recents);
    fix(favorites);
    await _p.setStringList('recents', recents);
    await _p.setStringList('favorites', favorites);
    notifyListeners();
  }

  Future<void> addRoot(String path) async {
    if (!authorizedRoots.contains(path)) authorizedRoots.add(path);
    await _p.setStringList('roots', authorizedRoots);
    notifyListeners();
  }

  Future<void> removeRoot(String path) async {
    authorizedRoots.remove(path);
    await _p.setStringList('roots', authorizedRoots);
    notifyListeners();
  }
}

/// Caché de miniaturas: memoria + disco (carpeta "thumbs" en el caché de la app).
/// La clave incluye ruta, tamaño y fecha de modificación, así que se invalida sola.
class ThumbCache {
  static final Map<String, Uint8List> _mem = {};
  static Directory? _dir;

  static Future<Uint8List?> get(File f) async {
    try {
      final st = await f.stat();
      final key = '${f.path}|${st.size}|${st.modified.millisecondsSinceEpoch}'
          .hashCode
          .toUnsigned(32)
          .toRadixString(16);
      final hit = _mem[key];
      if (hit != null) return hit;
      _dir ??= Directory('${(await getTemporaryDirectory()).path}/thumbs');
      await _dir!.create(recursive: true);
      final cf = File('${_dir!.path}/$key.png');
      if (await cf.exists()) {
        return _mem[key] = await cf.readAsBytes();
      }
      final codec = await ui.instantiateImageCodec(await f.readAsBytes(),
          targetWidth: 160);
      final frame = await codec.getNextFrame();
      final data =
          await frame.image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return null;
      final bytes = data.buffer.asUint8List();
      await cf.writeAsBytes(bytes);
      return _mem[key] = bytes;
    } catch (_) {
      return null; // imagen corrupta o ilegible: se muestra un icono
    }
  }

  static Future<void> clear() async {
    _mem.clear();
    try {
      final d = Directory('${(await getTemporaryDirectory()).path}/thumbs');
      if (await d.exists()) await d.delete(recursive: true);
    } catch (_) {}
  }
}

/// Crea archivos de ejemplo en el espacio propio de la app la primera vez.
Future<void> seedSamples(Directory root) async {
  final marker = File('${root.path}/.seeded');
  if (await marker.exists()) return;
  await File('${root.path}/leeme.txt').writeAsString(
      'Gestor de archivos - Práctica 4\nEscuela Superior de Cómputo, IPN.\n\n'
      'Este archivo vive en el espacio privado de la aplicación.\n');
  await File('${root.path}/notas.md').writeAsString(
      '# Notas\n\n- Soporta **Markdown** como texto\n- JSON y XML con colores\n'
      '- Imágenes con zoom y rotación\n');
  await File('${root.path}/datos.json').writeAsString(const JsonEncoder.withIndent('  ').convert({
    'curso': 'Desarrollo de aplicaciones móviles nativas',
    'practica': 4,
    'activo': true,
    'temas': ['Guinda', 'Azul'],
    'api': {'minAndroid': 24, 'minIOS': 15},
    'nulo': null,
  }));
  await File('${root.path}/config.xml').writeAsString(
      '<?xml version="1.0" encoding="UTF-8"?>\n<!-- Configuración de ejemplo -->\n'
      '<config version="1.0">\n  <tema nombre="guinda" activo="true"/>\n'
      '  <escuela>ESCOM</escuela>\n</config>\n');
  await Directory('${root.path}/Documentos').create();
  await File('${root.path}/Documentos/tarea.txt')
      .writeAsString('Archivo dentro de una subcarpeta.\n');
  // Imagen de ejemplo generada con dart:ui
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  const s = 512.0;
  c.drawRect(const Rect.fromLTWH(0, 0, s, s),
      Paint()..shader = ui.Gradient.linear(Offset.zero, const Offset(s, s), [const Color(0xFF6A1B3A), const Color(0xFF0D47A1)]));
  c.drawCircle(const Offset(256, 256), 140, Paint()..color = const Color(0xFFFFFFFF));
  c.drawRect(const Rect.fromLTWH(150, 230, 212, 52), Paint()..color = const Color(0xFF6A1B3A));
  final img = await rec.endRecording().toImage(512, 512);
  final bd = await img.toByteData(format: ui.ImageByteFormat.png);
  if (bd != null) {
    await File('${root.path}/imagen_demo.png').writeAsBytes(bd.buffer.asUint8List());
  }
  await marker.writeAsString('1');
}
