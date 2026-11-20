import 'package:flutter/material.dart';

import 'pantalla_mapa.dart';

void main() {
  runApp(const LocalizadorApp());
}

class LocalizadorApp extends StatelessWidget {
  const LocalizadorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Localizador de Puntos de Interés',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF0284C7),
        useMaterial3: true,
      ),
      home: const PantallaMapa(),
    );
  }
}