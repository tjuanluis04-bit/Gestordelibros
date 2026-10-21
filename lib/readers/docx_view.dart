import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:xml/xml.dart';

import '../services/archive_util.dart';

class _Run {
  final String text;
  final bool bold;
  final bool italic;
  _Run(this.text, this.bold, this.italic);
}

class _Para {
  final List<_Run> runs;
  final int heading;
  final bool bullet;
  _Para(this.runs, this.heading, this.bullet);
}

bool _on(XmlElement? e) {
  if (e == null) return false;
  final v = e.getAttribute('w:val');
  return v != '0' && v != 'false';
}

List<_Para> _parseDocx(List<int> bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final f = archive.findFile('word/document.xml');
  if (f == null) throw const FormatException('DOCX no válido');
  final doc = XmlDocument.parse(utf8.decode(archiveBytes(f), allowMalformed: true));
  final paras = <_Para>[];
  for (final para in doc.findAllElements('w:p')) {
    final pPr = para.getElement('w:pPr');
    final style = pPr?.getElement('w:pStyle')?.getAttribute('w:val')?.toLowerCase() ?? '';
    var heading = 0;
    if (style.startsWith('heading') || style.startsWith('ttulo') || style.startsWith('título')) {
      heading = int.tryParse(RegExp(r'\d').firstMatch(style)?.group(0) ?? '') ?? 1;
    } else if (style == 'title') {
      heading = 1;
    }
    final bullet = pPr?.getElement('w:numPr') != null;
    final runs = <_Run>[];
    for (final r in para.findAllElements('w:r')) {
      final rPr = r.getElement('w:rPr');
      final sb = StringBuffer();
      for (final c in r.childElements) {
        switch (c.name.local) {
          case 't':
            sb.write(c.innerText);
          case 'tab':
            sb.write('\t');
          case 'br':
            sb.write('\n');
        }
      }
      if (sb.isNotEmpty) runs.add(_Run(sb.toString(), _on(rPr?.getElement('w:b')), _on(rPr?.getElement('w:i'))));
    }
    paras.add(_Para(runs, heading, bullet));
  }
  return paras;
}

class DocxView extends StatefulWidget {
  final String path;
  final double fontSize;
  const DocxView({super.key, required this.path, required this.fontSize});

  @override
  State<DocxView> createState() => _DocxViewState();
}

class _DocxViewState extends State<DocxView> {
  late final Future<List<_Para>> _future =
      File(widget.path).readAsBytes().then(_parseDocx);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder<List<_Para>>(
      future: _future,
      builder: (_, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('No se pudo abrir el DOCX', style: TextStyle(color: cs.error)));
        }
        final paras = snap.data!;
        final base = TextStyle(fontSize: widget.fontSize, height: 1.55, color: cs.onSurface);
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          itemCount: paras.length,
          itemBuilder: (_, i) {
            final para = paras[i];
            if (para.runs.isEmpty) return SizedBox(height: widget.fontSize * .6);
            final scale = para.heading == 0 ? 1.0 : (para.heading == 1 ? 1.5 : (para.heading == 2 ? 1.3 : 1.15));
            return Padding(
              padding: EdgeInsets.only(bottom: 10, top: para.heading > 0 ? 8 : 0),
              child: Text.rich(
                TextSpan(
                  style: base.copyWith(
                    fontSize: widget.fontSize * scale,
                    fontWeight: para.heading > 0 ? FontWeight.w700 : null,
                  ),
                  children: [
                    if (para.bullet) const TextSpan(text: '•  '),
                    for (final r in para.runs)
                      TextSpan(
                        text: r.text,
                        style: TextStyle(
                          fontWeight: r.bold ? FontWeight.w700 : null,
                          fontStyle: r.italic ? FontStyle.italic : null,
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
