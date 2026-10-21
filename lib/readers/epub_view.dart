import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:path/path.dart' as p;
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';

import '../services/archive_util.dart';

// ───────────────────────── Modelo y parser ─────────────────────────

class _Chapter {
  final String path;
  final String html;
  _Chapter(this.path, this.html);
}

class _TocItem {
  final String title;
  final int chapter;
  final int depth;
  _TocItem(this.title, this.chapter, this.depth);
}

class _EpubData {
  final String id;
  final String title;
  final String author;
  final Uint8List? cover;
  final List<_Chapter> chapters;
  final List<_TocItem> toc;
  _EpubData(this.id, this.title, this.author, this.cover, this.chapters, this.toc);
}

class _Mark {
  final int item;
  final String title;
  _Mark(this.item, this.title);
}

Iterable<XmlElement> _els(XmlNode n, String local) =>
    n.descendants.whereType<XmlElement>().where((e) => e.name.local == local);

String _text(ArchiveFile f) => utf8.decode(archiveBytes(f), allowMalformed: true);

String _clean(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

String _dec(String s) {
  try {
    return Uri.decodeFull(s);
  } catch (_) {
    return s;
  }
}

_EpubData _parseEpub(List<int> bytes) {
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
  String? rootPath;
  for (final e in _els(XmlDocument.parse(_text(container)), 'rootfile')) {
    rootPath = e.getAttribute('full-path');
    if (rootPath != null) break;
  }
  if (rootPath == null) throw const FormatException('EPUB sin OPF');
  final opfFile = find(rootPath);
  if (opfFile == null) throw const FormatException('EPUB sin OPF');

  final opf = XmlDocument.parse(_text(opfFile));
  final opfDir = p.posix.dirname(rootPath);

  String resolve(String baseDir, String href) {
    final clean = _dec(href.split('#').first);
    return p.posix.normalize(baseDir == '.' || baseDir.isEmpty ? clean : p.posix.join(baseDir, clean));
  }

  // manifest
  final manifest = <String, Map<String, String>>{};
  for (final item in _els(opf, 'item')) {
    final id = item.getAttribute('id');
    final href = item.getAttribute('href');
    if (id == null || href == null) continue;
    manifest[id] = {
      'href': href,
      'type': item.getAttribute('media-type') ?? '',
      'props': item.getAttribute('properties') ?? '',
    };
  }

  // metadatos
  String firstText(String local) {
    for (final e in _els(opf, local)) {
      final t = _clean(e.innerText);
      if (t.isNotEmpty) return t;
    }
    return '';
  }

  final title = firstText('title');
  final author = firstText('creator');
  var bookId = firstText('identifier');
  if (bookId.isEmpty) bookId = title;

  // portada
  String? coverHref;
  for (final m in _els(opf, 'meta')) {
    if (m.getAttribute('name') == 'cover') {
      final ref = manifest[m.getAttribute('content')];
      if (ref != null) coverHref = ref['href'];
    }
  }
  if (coverHref == null) {
    for (final m in manifest.values) {
      if ((m['props'] ?? '').contains('cover-image')) {
        coverHref = m['href'];
        break;
      }
    }
  }
  if (coverHref == null) {
    for (final e in manifest.entries) {
      final t = e.value['type'] ?? '';
      final h = (e.value['href'] ?? '').toLowerCase();
      if (t.startsWith('image/') && (e.key.toLowerCase().contains('cover') || h.contains('cover'))) {
        coverHref = e.value['href'];
        break;
      }
    }
  }
  Uint8List? cover;
  if (coverHref != null) {
    final cf = find(resolve(opfDir, coverHref));
    if (cf != null) cover = Uint8List.fromList(archiveBytes(cf));
  }

  // capítulos (orden de lectura)
  final chapters = <_Chapter>[];
  final pathIndex = <String, int>{};
  void addChapter(String href) {
    final full = resolve(opfDir, href);
    if (pathIndex.containsKey(full)) return;
    final f = find(full);
    if (f == null) return;
    final html = _text(f);
    if (html.trim().isEmpty) return;
    pathIndex[full] = chapters.length;
    chapters.add(_Chapter(full, html));
  }

  for (final ref in _els(opf, 'itemref')) {
    final it = manifest[ref.getAttribute('idref')];
    if (it != null) addChapter(it['href']!);
  }
  if (chapters.isEmpty) {
    for (final it in manifest.values) {
      final l = (it['href'] ?? '').toLowerCase();
      if (l.endsWith('.xhtml') || l.endsWith('.html') || l.endsWith('.htm')) addChapter(it['href']!);
    }
  }

  // índice (EPUB3 nav o EPUB2 NCX)
  final toc = <_TocItem>[];
  void addToc(String t, String href, String baseDir, int depth) {
    final idx = pathIndex[resolve(baseDir, href)];
    if (idx == null || t.isEmpty) return;
    toc.add(_TocItem(t, idx, depth));
  }

  Map<String, String>? navItem;
  Map<String, String>? ncxItem;
  for (final m in manifest.values) {
    if ((m['props'] ?? '').split(' ').contains('nav')) navItem = m;
    if (m['type'] == 'application/x-dtbncx+xml') ncxItem = m;
  }

  try {
    if (navItem != null) {
      final navPath = resolve(opfDir, navItem['href']!);
      final nf = find(navPath);
      if (nf != null) {
        final navDir = p.posix.dirname(navPath);
        final doc = XmlDocument.parse(_text(nf));
        XmlElement? nav;
        for (final n in _els(doc, 'nav')) {
          if (n.attributes.any((a) => a.name.local == 'type' && a.value.contains('toc'))) {
            nav = n;
            break;
          }
        }
        if (nav == null) {
          for (final n in _els(doc, 'nav')) {
            nav = n;
            break;
          }
        }
        if (nav != null) {
          for (final a in _els(nav, 'a')) {
            final href = a.getAttribute('href');
            if (href == null) continue;
            var d = 0;
            XmlNode? n = a.parent;
            while (n != null && n != nav) {
              if (n is XmlElement && n.name.local == 'ol') d++;
              n = n.parent;
            }
            addToc(_clean(a.innerText), href, navDir, d > 0 ? d - 1 : 0);
          }
        }
      }
    }
  } catch (_) {}

  try {
    if (toc.isEmpty && ncxItem != null) {
      final ncxPath = resolve(opfDir, ncxItem['href']!);
      final nf = find(ncxPath);
      if (nf != null) {
        final ncxDir = p.posix.dirname(ncxPath);
        final doc = XmlDocument.parse(_text(nf));
        void walk(XmlElement parent, int depth) {
          for (final np in parent.childElements.where((c) => c.name.local == 'navPoint')) {
            var label = '';
            for (final e in _els(np, 'text')) {
              label = _clean(e.innerText);
              if (label.isNotEmpty) break;
            }
            for (final c in _els(np, 'content')) {
              final src = c.getAttribute('src');
              if (src != null) addToc(label, src, ncxDir, depth);
              break;
            }
            walk(np, depth + 1);
          }
        }

        for (final navMap in _els(doc, 'navMap')) {
          walk(navMap, 0);
          break;
        }
      }
    }
  } catch (_) {}

  return _EpubData(bookId, title, author, cover, chapters, toc);
}

// ───────────────────────── Vista ─────────────────────────

class EpubBookView extends StatefulWidget {
  final String path;
  final double fontSize;
  const EpubBookView({super.key, required this.path, required this.fontSize});

  @override
  State<EpubBookView> createState() => _EpubBookViewState();
}

class _EpubBookViewState extends State<EpubBookView> {
  late final Future<_EpubData> _future =
      File(widget.path).readAsBytes().then((b) => compute(_parseEpub, b));
  final _scroll = ItemScrollController();
  final _positions = ItemPositionsListener.create();
  List<_Mark> _marks = [];
  _EpubData? _data;

  @override
  void initState() {
    super.initState();
    _future.then((d) async {
      _data = d;
      _marks = await _loadMarks(d.id);
      if (mounted) setState(() {});
    }).catchError((_) {});
  }

  String _key(String id) => 'epub_marks_$id';

  Future<List<_Mark>> _loadMarks(String id) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_key(id));
      if (raw == null) return [];
      return (jsonDecode(raw) as List).map((e) => _Mark(e['item'] as int, e['title'] as String)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveMarks() async {
    final d = _data;
    if (d == null) return;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_key(d.id), jsonEncode(_marks.map((m) => {'item': m.item, 'title': m.title}).toList()));
  }

  int _currentItem() {
    final v = _positions.itemPositions.value.where((e) => e.itemTrailingEdge > 0).toList();
    if (v.isEmpty) return 0;
    v.sort((a, b) => a.index.compareTo(b.index));
    return v.first.index;
  }

  String _titleFor(_EpubData d, int item) {
    if (item <= 0) return 'Portada';
    final ch = item - 1;
    String? best;
    for (final t in d.toc) {
      if (t.chapter <= ch) {
        best = t.title;
      } else {
        break;
      }
    }
    return best ?? 'Capítulo $item';
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _addMark({bool quiet = false}) async {
    final d = _data;
    if (d == null) return;
    final item = _currentItem();
    if (_marks.any((m) => m.item == item)) {
      if (!quiet) _toast('Ya hay un marcador en este capítulo');
      return;
    }
    setState(() {
      _marks.add(_Mark(item, _titleFor(d, item)));
      _marks.sort((a, b) => a.item.compareTo(b.item));
    });
    await _saveMarks();
    if (!quiet && mounted) _toast('Marcador añadido');
  }

  void _jump(int item) => _scroll.jumpTo(index: item);

  void _openSheet(_EpubData d) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SizedBox(
          height: MediaQuery.of(ctx).size.height * .75,
          child: DefaultTabController(
            length: 2,
            child: Column(
              children: [
                const TabBar(tabs: [Tab(text: 'Índice'), Tab(text: 'Marcadores')]),
                Expanded(
                  child: TabBarView(children: [_tocTab(d, ctx), _marksTab(d, ctx, setSheet)]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tocTab(_EpubData d, BuildContext ctx) {
    if (d.toc.isEmpty) {
      return ListView.builder(
        itemCount: d.chapters.length,
        itemBuilder: (_, i) => ListTile(
          title: Text('Capítulo ${i + 1}'),
          onTap: () {
            Navigator.pop(ctx);
            _jump(i + 1);
          },
        ),
      );
    }
    return ListView.builder(
      itemCount: d.toc.length,
      itemBuilder: (_, i) {
        final t = d.toc[i];
        return ListTile(
          dense: t.depth > 0,
          contentPadding: EdgeInsets.only(left: 16.0 + t.depth * 18, right: 16),
          title: Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          onTap: () {
            Navigator.pop(ctx);
            _jump(t.chapter + 1);
          },
        );
      },
    );
  }

  Widget _marksTab(_EpubData d, BuildContext ctx, StateSetter setSheet) {
    final cs = Theme.of(ctx).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: () async {
                await _addMark(quiet: true);
                setSheet(() {});
              },
              icon: const Icon(Icons.bookmark_add_rounded),
              label: const Text('Añadir marcador aquí'),
            ),
          ),
        ),
        Expanded(
          child: _marks.isEmpty
              ? Center(child: Text('Aún no tienes marcadores', style: TextStyle(color: cs.onSurfaceVariant)))
              : ListView.builder(
                  itemCount: _marks.length,
                  itemBuilder: (_, i) {
                    final m = _marks[i];
                    return ListTile(
                      leading: Icon(Icons.bookmark_rounded, color: cs.tertiary),
                      title: Text(m.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline_rounded),
                        onPressed: () async {
                          setState(() => _marks.remove(m));
                          setSheet(() {});
                          await _saveMarks();
                        },
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        _jump(m.item);
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _header(_EpubData d, BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    if (d.cover == null && d.title.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        if (d.cover != null)
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 460),
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: Image.memory(
                  d.cover!,
                  fit: BoxFit.contain,
                  cacheWidth: 900,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        if (d.title.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(d.title, textAlign: TextAlign.center, style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        ],
        if (d.author.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(d.author, textAlign: TextAlign.center, style: tt.titleMedium?.copyWith(color: cs.onSurfaceVariant)),
        ],
        const SizedBox(height: 8),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder<_EpubData>(
      future: _future,
      builder: (_, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError || snap.data == null || snap.data!.chapters.isEmpty) {
          return Center(child: Text('No se pudo abrir el EPUB', style: TextStyle(color: cs.error)));
        }
        final d = snap.data!;
        final style = TextStyle(fontSize: widget.fontSize, height: 1.6, color: cs.onSurface);
        return Stack(
          children: [
            ScrollablePositionedList.separated(
              itemScrollController: _scroll,
              itemPositionsListener: _positions,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
              itemCount: d.chapters.length + 1,
              itemBuilder: (_, i) =>
                  i == 0 ? _header(d, context) : HtmlWidget(d.chapters[i - 1].html, textStyle: style),
              separatorBuilder: (_, __) => const Divider(height: 40),
            ),
            Positioned(
              right: 16,
              bottom: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton.small(
                    heroTag: null,
                    tooltip: 'Añadir marcador',
                    onPressed: () => _addMark(),
                    child: const Icon(Icons.bookmark_add_rounded),
                  ),
                  const SizedBox(height: 10),
                  FloatingActionButton.small(
                    heroTag: null,
                    tooltip: 'Índice y marcadores',
                    onPressed: () => _openSheet(d),
                    child: const Icon(Icons.bookmarks_rounded),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
