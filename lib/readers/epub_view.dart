import 'dart:io';

import 'package:epubx/epubx.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

class EpubBookView extends StatefulWidget {
  final String path;
  final double fontSize;
  const EpubBookView({super.key, required this.path, required this.fontSize});

  @override
  State<EpubBookView> createState() => _EpubBookViewState();
}

class _EpubBookViewState extends State<EpubBookView> {
  late final Future<List<String>> _future = _load();

  Future<List<String>> _load() async {
    final bytes = await File(widget.path).readAsBytes();
    final book = await EpubReader.readBook(bytes);
    final out = <String>[];
    final html = book.Content?.Html ?? {};
    final manifest = book.Schema?.Package?.Manifest?.Items ?? [];
    final spine = book.Schema?.Package?.Spine?.Items ?? [];
    for (final ref in spine) {
      for (final m in manifest) {
        if (m.Id == ref.IdRef) {
          final c = html[m.Href]?.Content;
          if (c != null && c.trim().isNotEmpty) out.add(c);
          break;
        }
      }
    }
    if (out.isEmpty) {
      for (final f in html.values) {
        final c = f.Content;
        if (c != null && c.trim().isNotEmpty) out.add(c);
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder<List<String>>(
      future: _future,
      builder: (_, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError || (snap.data?.isEmpty ?? true)) {
          return Center(child: Text('No se pudo abrir el EPUB', style: TextStyle(color: cs.error)));
        }
        final chapters = snap.data!;
        final style = TextStyle(fontSize: widget.fontSize, height: 1.6, color: cs.onSurface);
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          itemCount: chapters.length,
          separatorBuilder: (_, __) => const Divider(height: 40),
          itemBuilder: (_, i) => HtmlWidget(chapters[i], textStyle: style),
        );
      },
    );
  }
}
