import 'package:flutter/material.dart';
import 'model.dart';
import 'pages.dart';

final store = Store();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await store.init();
  runApp(const ApagonApp());
}

class ApagonApp extends StatelessWidget {
  const ApagonApp({super.key});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, child) => MaterialApp(
        title: 'Apagón',
        debugShowCheckedModeBanner: false,
        theme: store.palette.theme(Brightness.light),
        darkTheme: store.palette.theme(Brightness.dark),
        themeMode: ThemeMode.system, // claro/oscuro según el sistema
        home: const MenuPage(),
      ),
    );
  }
}
