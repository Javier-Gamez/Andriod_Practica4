import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_archivos/main.dart' as app;
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

/// Prueba de integración (Android e iOS) del gestor de archivos.
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
    await binding.takeScreenshot('p1_${plat}_$name');
  }

  Finder tile(String name) => find.widgetWithText(ListTile, name);
  Finder menuOf(String name) => find.descendant(of: tile(name), matching: find.byIcon(Icons.more_vert));

  Future<void> tapTile(WidgetTester t, String name) async {
    await t.ensureVisible(tile(name));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(tile(name));
  }

  Future<void> tapMenu(WidgetTester t, String name) async {
    await t.ensureVisible(menuOf(name));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(menuOf(name));
  }

  testWidgets('Gestor: flujo completo', (t) async {
    app.main();
    await settle(t);
    final docs = await getApplicationDocumentsDirectory();
    // Archivos extra para probar JSON inválido y formato no soportado
    File('${docs.path}/roto.json').writeAsStringSync('{"a": ');
    File('${docs.path}/datos.bin').writeAsBytesSync([0, 1, 2, 3]);
    for (final n in ['leeme_nuevo.txt', 'Documentos/leeme_nuevo.txt']) {
      final f = File('${docs.path}/$n');
      if (f.existsSync()) f.deleteSync();
    }
    await shot(t, '01_explorar');

    // --- Navegar al espacio de la app ---
    await t.tap(find.text('Espacio de la aplicación'));
    await settle(t);
    await shot(t, '02_espacio_app');
    expect(find.text('datos.json'), findsOneWidget);

    // --- JSON, XML, TXT, imagen ---
    await tapTile(t, 'datos.json');
    await settle(t);
    await shot(t, '03_json');
    await t.pageBack();
    await settle(t);

    await tapTile(t, 'config.xml');
    await settle(t);
    await shot(t, '04_xml');
    await t.pageBack();
    await settle(t);

    await tapTile(t, 'leeme.txt');
    await settle(t);
    expect(find.textContaining('Práctica 4', findRichText: true), findsOneWidget);
    await t.pageBack();
    await settle(t);

    await tapTile(t, 'roto.json');
    await settle(t);
    await shot(t, '05_json_invalido');
    expect(find.textContaining('JSON inválido'), findsOneWidget);
    await t.pageBack();
    await settle(t);

    await tapTile(t, 'imagen_demo.png');
    await settle(t);
    await t.tap(find.byIcon(Icons.rotate_right));
    await settle(t);
    await shot(t, '06_imagen_rotada');
    await t.tap(find.byIcon(Icons.info_outline));
    await settle(t);
    await shot(t, '07_metadatos');
    expect(find.textContaining('image/png'), findsOneWidget);
    await t.tap(find.text('Cerrar'));
    await settle(t);
    await t.pageBack();
    await settle(t);

    // --- Formato no soportado ---
    await tapTile(t, 'datos.bin');
    await settle(t);
    await shot(t, '08_formato_no_soportado');
    expect(find.text('Formato no soportado'), findsOneWidget);
    await t.tapAt(const Offset(5, 5));
    await settle(t);

    // --- Renombrar ---
    await tapMenu(t, 'leeme.txt');
    await settle(t);
    await shot(t, '09_menu_archivo');
    await t.tap(find.text('Renombrar'));
    await settle(t);
    await t.enterText(find.byType(TextField), 'leeme_nuevo.txt');
    await t.tap(find.text('Aceptar'));
    await settle(t);
    expect(find.text('leeme_nuevo.txt'), findsOneWidget);
    expect(File('${docs.path}/leeme_nuevo.txt').existsSync(), isTrue);

    // --- Favorito ---
    await tapMenu(t, 'leeme_nuevo.txt');
    await settle(t);
    await t.tap(find.text('Agregar a favoritos'));
    await settle(t);
    expect(app.prefs.isFav('${docs.path}/leeme_nuevo.txt'), isTrue);

    // --- Copiar a Documentos ---
    await tapMenu(t, 'leeme_nuevo.txt');
    await settle(t);
    await t.tap(find.text('Copiar a...'));
    await settle(t);
    await t.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Documentos')));
    await settle(t);
    await shot(t, '10_elegir_destino');
    await t.tap(find.text('Seleccionar aquí'));
    await settle(t);
    expect(File('${docs.path}/Documentos/leeme_nuevo.txt').existsSync(), isTrue);

    // --- Mover (a Documentos con otro nombre para evitar choque) ---
    File('${docs.path}/mover.txt').writeAsStringSync('mover');
    await t.tap(find.byIcon(Icons.refresh));
    await settle(t);
    await tapMenu(t, 'mover.txt');
    await settle(t);
    await t.tap(find.text('Mover a...'));
    await settle(t);
    await t.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Documentos')));
    await settle(t);
    await t.tap(find.text('Seleccionar aquí'));
    await settle(t);
    expect(File('${docs.path}/Documentos/mover.txt').existsSync(), isTrue);
    expect(File('${docs.path}/mover.txt').existsSync(), isFalse);

    // --- Eliminar con confirmación ---
    await tapMenu(t, 'leeme_nuevo.txt');
    await settle(t);
    await t.ensureVisible(find.text('Eliminar'));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('Eliminar'));
    await settle(t);
    await shot(t, '11_confirmar_eliminar');
    await t.tap(find.text('Aceptar'));
    await settle(t);
    expect(File('${docs.path}/leeme_nuevo.txt').existsSync(), isFalse);

    // --- Breadcrumbs: entrar a Documentos ---
    await tapTile(t, 'Documentos');
    await settle(t);
    await shot(t, '12_breadcrumbs');
    expect(find.widgetWithText(ActionChip, 'Documentos'), findsOneWidget);
    await t.pageBack(); // vuelve a la raíz del navegador
    await settle(t);
    await t.pageBack(); // vuelve al inicio
    await settle(t);

    // --- Recientes, favoritos y tema Azul ---
    await t.tap(find.text('Recientes'));
    await settle(t);
    await shot(t, '13_recientes');
    await t.tap(find.text('Favoritos'));
    await settle(t);
    await shot(t, '14_favoritos');
    await t.tap(find.text('Ajustes'));
    await settle(t);
    await t.tap(find.text('Azul (ESCOM)'));
    await settle(t);
    await shot(t, '15_tema_azul');
    expect(app.prefs.palette.name, 'azul');
  });
}
