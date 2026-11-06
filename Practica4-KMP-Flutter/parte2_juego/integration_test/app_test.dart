import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:juego_partidas/main.dart' as app;
import 'package:shared_preferences/shared_preferences.dart';

/// Prueba de integración (Android e iOS): recorre el juego, guarda en los
/// tres formatos, valida archivos dañados y toma capturas con nombre fijo.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final plat = Platform.isIOS ? 'ios' : 'android';

  var converted = false;

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 250));
    }
  }

  Future<void> shot(WidgetTester t, String name) async {
    await settle(t);
    if (Platform.isAndroid && !converted) {
      await binding.convertFlutterSurfaceToImage();
      converted = true;
    }
    await t.pump();
    await binding.takeScreenshot('p2_${plat}_$name');
  }

  testWidgets('Apagón: flujo completo', (t) async {
    // Desbloquea el nivel 2 para poder probarlo.
    final sp = await SharedPreferences.getInstance();
    await sp.setInt('unlocked', 2);
    app.main();
    await settle(t);
    // Limpia partidas previas para una prueba determinista.
    for (final e in app.store.dir.listSync()) {
      if (e is File) e.deleteSync();
    }
    await t.pump(const Duration(seconds: 1));
    await shot(t, '01_menu');

    // --- Guardar una partida en cada formato ---
    for (final fmt in ['txt', 'xml', 'json']) {
      await t.tap(find.textContaining('Nivel 1').first);
      await settle(t);
      await t.tap(find.byType(AnimatedContainer).at(0));
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.byType(AnimatedContainer).at(4));
      await t.pump(const Duration(milliseconds: 300));
      if (fmt == 'txt') await shot(t, '02_juego');
      await t.tap(find.text('Guardar').first);
      await settle(t);
      await t.tap(find.text('.$fmt'));
      await t.pump(const Duration(milliseconds: 300));
      if (fmt == 'xml') await shot(t, '03_dialogo_guardar');
      await t.tap(find.text('Guardar').last);
      await settle(t);
      await t.pageBack();
      await settle(t);
    }

    // --- Los tres archivos existen y son válidos ---
    final list = await app.store.list();
    expect(list.where((e) => e.state != null).map((e) => e.ext).toSet(), {'txt', 'xml', 'json'});
    for (final e in list) {
      expect(e.error, isNull);
      expect(e.state!.moves.length, 2);
    }

    // --- Archivos dañados: no bloquean la lista ---
    File('${app.store.dir.path}/vacia.json').writeAsStringSync('');
    File('${app.store.dir.path}/rota.txt').writeAsStringSync('APAGON-SAVE v1\nid=1\n');
    File('${app.store.dir.path}/mala.xml').writeAsStringSync('<partida><id>1</id>');
    await t.tap(find.text('Partidas guardadas'));
    await settle(t);
    await t.pump(const Duration(seconds: 1));
    await shot(t, '04_lista_partidas');
    expect(find.textContaining('Dañada'), findsNWidgets(3));
    expect(find.text('Partida'), findsNWidgets(3));

    // Ver contenido de una partida
    await t.tap(find.byType(PopupMenuButton<String>).last);
    await settle(t);
    await t.tap(find.text('Ver contenido'));
    await settle(t);
    await shot(t, '05_ver_contenido');
    await t.tapAt(const Offset(5, 5));
    await settle(t);
    await t.pageBack();
    await settle(t);

    // --- Continuar tras "reinicio" (la partida se lee de disco) ---
    expect(await app.store.latest(), isNotNull);

    // --- Opciones y tema Azul ---
    await t.tap(find.text('Opciones'));
    await settle(t);
    await t.tap(find.text('Azul (ESCOM)'));
    await settle(t);
    await shot(t, '06_opciones_azul');
    expect(app.store.palette.name, 'azul');
    await t.pageBack();
    await settle(t);
    await shot(t, '07_menu_azul');

    // --- Nivel 2 (5x5) ---
    await t.tap(find.textContaining('Nivel 2'));
    await settle(t);
    expect(find.byType(AnimatedContainer), findsNWidgets(25));
    await t.tap(find.byType(AnimatedContainer).at(12));
    await t.pump(const Duration(milliseconds: 300));
    await shot(t, '08_nivel2');
    // Deshacer revierte el movimiento
    await t.tap(find.text('Deshacer'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('0 mov.'), findsOneWidget);
  });
}
