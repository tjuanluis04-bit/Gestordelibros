import 'package:flutter/material.dart';

import 'screens/browser_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
