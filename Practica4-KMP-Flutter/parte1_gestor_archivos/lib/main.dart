import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'home.dart';
import 'storage.dart';

final prefs = Prefs();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await prefs.load();
  // Espacio propio de la app (sandbox en iOS / almacenamiento interno en Android)
  final docs = await getApplicationDocumentsDirectory();
  await seedSamples(docs);
  runApp(const FileManagerApp());
}

class FileManagerApp extends StatelessWidget {
  const FileManagerApp({super.key});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: prefs,
      builder: (_, __) => MaterialApp(
        title: 'Gestor de archivos',
        debugShowCheckedModeBanner: false,
        theme: prefs.palette.theme(Brightness.light),
        darkTheme: prefs.palette.theme(Brightness.dark),
        themeMode: ThemeMode.system, // claro/oscuro automático
        home: const HomePage(),
      ),
    );
  }
}

// Exportado para que otros archivos accedan al directorio raíz propio.
Future<Directory> appRoot() => getApplicationDocumentsDirectory();
