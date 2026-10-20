import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'screens/browser_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize();
  // Muestra el error en pantalla en vez de dejar un hueco en blanco.
  ErrorWidget.builder = (details) => Material(
        color: const Color(0xFF2B1B1B),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Text(
                details.exceptionAsString(),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          ),
        ),
      );
  runApp(const BookManagerApp());
}

class BookManagerApp extends StatelessWidget {
  const BookManagerApp({super.key});

  ThemeData _theme(Brightness b) => ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF5B5BD6),
        brightness: b,
        appBarTheme: const AppBarTheme(centerTitle: false, scrolledUnderElevation: 0),
        snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gestor de Libros',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const BrowserScreen(),
    );
  }
}
