import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

class TextBookView extends StatefulWidget {
  final String path;
  final double fontSize;
  const TextBookView({super.key, required this.path, required this.fontSize});

  @override
  State<TextBookView> createState() => _TextBookViewState();
}

class _TextBookViewState extends State<TextBookView> {
  late final Future<List<String>> _future = File(widget.path)
      .readAsBytes()
      .then((b) => const LineSplitter().convert(utf8.decode(b, allowMalformed: true)));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder<List<String>>(
      future: _future,
      builder: (_, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('No se pudo abrir el archivo', style: TextStyle(color: cs.error)));
        }
        final lines = snap.data!;
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          itemCount: lines.length,
          itemBuilder: (_, i) => Text(
            lines[i].isEmpty ? ' ' : lines[i],
            style: TextStyle(fontSize: widget.fontSize, height: 1.55, color: cs.onSurface),
          ),
        );
      },
    );
  }
}
