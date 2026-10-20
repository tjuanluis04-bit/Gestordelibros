import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

Iterable<XmlElement> _els(XmlNode n, String local) =>
    n.descendants.whereType<XmlElement>().where((e) => e.name.local == local);

String _text(ArchiveFile f) => utf8.decode(f.content as List<int>, allowMalformed: true);

/// Devuelve el HTML de cada capítulo en orden de lectura (spine).
List<String> _parseEpub(List<int> bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);

  ArchiveFile? find(String name) {
    final exact = archive.findFile(name);
    if (exact != null) return exact;
    final lower = name.toLowerCase();
    for (final f in archive.files) {
      if (f.name.toLowerCase() == lower) return f;
    }
    return null;
  }

  final container = find('META-INF/container.xml');
  if (container == null) throw const FormatException('EPUB no válido');
  final rootPath = _els(XmlDocument.parse(_text(container)), 'rootfile')
      .map((e) => e.getAttribute('full-path'))
      .firstWhere((v) => v != null, orElse: () => null);
  if (rootPath == null) throw const FormatException('EPUB sin OPF');
  final opfFile = find(rootPath);
  if (opfFile == null) throw const FormatException('EPUB sin OPF');

  final opf = XmlDocument.parse(_text(opfFile));
  final opfDir = p.posix.dirname(rootPath);

  final hrefById = <String, String>{};
  for (final item in _els(opf, 'item')) {
    final id = item.getAttribute('id');
    final href = item.getAttribute('href');
    if (id != null && href != null) hrefById[id] = href;
  }

  final out = <String>[];
  void addHref(String href) {
    final clean = Uri.decodeFull(href.split('#').first);
    final full = p.posix.normalize(opfDir == '.' ? clean : p.posix.join(opfDir, clean));
    final f = find(full);
    if (f == null) return;
    final t = _text(f);
    if (t.trim().isNotEmpty) out.add(t);
  }

  for (final ref in _els(opf, 'itemref')) {
    final href = hrefById[ref.getAttribute('idref')];
    if (href != null) addHref(href);
  }
  if (out.isEmpty) {
    for (final href in hrefById.values) {
      final l = href.toLowerCase();
      if (l.endsWith('.xhtml') || l.endsWith('.html') || l.endsWith('.htm')) addHref(href);
    }
  }
  return out;
}

class EpubBookView extends StatefulWidget {
  final String path;
  final double fontSize;
  const EpubBookView({super.key, required this.path, required this.fontSize});

  @override
  State<EpubBookView> createState() => _EpubBookViewState();
}

class _EpubBookViewState extends State<EpubBookView> {
  late final Future<List<String>> _future =
      File(widget.path).readAsBytes().then(_parseEpub);

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
