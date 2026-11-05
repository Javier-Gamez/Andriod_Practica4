import 'package:flutter/material.dart';

/// Temas personalizables: Guinda (IPN) y Azul (ESCOM).
/// Cada uno genera su ColorScheme claro y oscuro; el modo se toma del sistema
/// (ThemeMode.system en MaterialApp).
enum AppPalette {
  guinda('Guinda (IPN)', Color(0xFF6A1B3A)),
  azul('Azul (ESCOM)', Color(0xFF0D47A1));

  final String label;
  final Color seed;
  const AppPalette(this.label, this.seed);

  ThemeData theme(Brightness b) => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: b),
        appBarTheme: const AppBarTheme(centerTitle: false),
      );
}
