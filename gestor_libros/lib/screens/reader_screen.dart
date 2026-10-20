import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../readers/docx_view.dart';
import '../readers/epub_view.dart';
import '../readers/text_view.dart';
import '../widgets/book_actions.dart';

class ReaderScreen extends StatefulWidget {
  final List<String> paths;
  final int index;
  const ReaderScreen({super.key, required this.paths, required this.index});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late final List<String> _paths = List.of(widget.paths);
  late int _i = widget.index;
  double _font = 17;

  String get _path => _paths[_i];
  String get _ext => p.extension(_path).toLowerCase();

  void _go(int d) {
    final n = _i + d;
    if (n < 0 || n >= _paths.length) return;
    setState(() => _i = n);
  }

  void _removeCurrent() {
    if (_paths.length == 1) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _paths.removeAt(_i);
      if (_i >= _paths.length) _i = _paths.length - 1;
    });
  }

  Future<void> _rename() async {
    final np = await renameBook(context, _path);
    if (np != null && mounted) setState(() => _paths[_i] = np);
  }

  Future<void> _move() async {
    if (await moveBook(context, _path) != null && mounted) _removeCurrent();
  }

  Future<void> _delete() async {
    if (await deleteBook(context, _path) && mounted) _removeCurrent();
  }

  void _fontSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Tamaño del texto', style: Theme.of(ctx).textTheme.titleMedium),
              Row(
                children: [
                  const Text('A', style: TextStyle(fontSize: 13)),
                  Expanded(
                    child: Slider(
                      value: _font,
                      min: 13,
                      max: 30,
                      divisions: 17,
                      label: _font.round().toString(),
                      onChanged: (v) {
                        setState(() => _font = v);
                        setSheet(() {});
                      },
                    ),
                  ),
                  const Text('A', style: TextStyle(fontSize: 26)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _book() {
    final key = ValueKey(_path);
    switch (_ext) {
      case '.pdf':
        return PdfViewer.file(_path, key: key);
      case '.epub':
        return EpubBookView(key: key, path: _path, fontSize: _font);
      case '.docx':
        return DocxView(key: key, path: _path, fontSize: _font);
      default:
        return TextBookView(key: key, path: _path, fontSize: _font);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(p.basenameWithoutExtension(_path),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
            Text('${_i + 1} de ${_paths.length} · ${_ext.substring(1).toUpperCase()}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ],
        ),
        actions: [
          if (_ext != '.pdf')
            IconButton(icon: const Icon(Icons.text_fields_rounded), tooltip: 'Texto', onPressed: _fontSheet),
          IconButton(icon: const Icon(Icons.edit_rounded), tooltip: 'Renombrar', onPressed: _rename),
          PopupMenuButton<String>(
            onSelected: (a) => a == 'move' ? _move() : _delete(),
            itemBuilder: (_) => [
              const PopupMenuItem(
                  value: 'move',
                  child: ListTile(leading: Icon(Icons.drive_file_move_rounded), title: Text('Mover'))),
              PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                      leading: Icon(Icons.delete_rounded, color: cs.error),
                      title: Text('Eliminar', style: TextStyle(color: cs.error)))),
            ],
          ),
        ],
      ),
      body: _book(),
      bottomNavigationBar: Material(
        color: cs.surfaceContainer,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: _i > 0 ? () => _go(-1) : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                  label: const Text('Anterior'),
                ),
                Expanded(
                  child: Center(
                    child: Text('${_i + 1} / ${_paths.length}',
                        style: Theme.of(context).textTheme.labelLarge),
                  ),
                ),
                FilledButton.tonal(
                  onPressed: _i < _paths.length - 1 ? () => _go(1) : null,
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('Siguiente'),
                    SizedBox(width: 4),
                    Icon(Icons.chevron_right_rounded),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
