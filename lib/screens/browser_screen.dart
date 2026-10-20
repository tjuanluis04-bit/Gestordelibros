import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';

import '../services/file_ops.dart';
import '../widgets/book_actions.dart';
import 'reader_screen.dart';

Color extColor(String ext) {
  switch (ext) {
    case '.pdf':
      return const Color(0xFFE5484D);
    case '.epub':
      return const Color(0xFF30A46C);
    case '.docx':
      return const Color(0xFF3E63DD);
    default:
      return const Color(0xFF8B8D98);
  }
}

class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key});

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> with WidgetsBindingObserver {
  String _dir = storageRoot;
  bool? _access;
  bool _loading = false;
  String? _error;
  List<Entry> _entries = [];
  SortMode _sort = SortMode.name;
  bool _searching = false;
  final _query = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAccess();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _query.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _access != true) _checkAccess();
  }

  Future<void> _checkAccess() async {
    final ok = await Permission.manageExternalStorage.isGranted || await Permission.storage.isGranted;
    if (!mounted) return;
    setState(() => _access = ok);
    if (ok) _load();
  }

  Future<void> _requestAccess() async {
    var st = await Permission.manageExternalStorage.request();
    if (!st.isGranted) st = await Permission.storage.request();
    await _checkAccess();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await FileOps.list(_dir, _sort);
      if (!mounted) return;
      setState(() {
        _entries = r;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _entries = [];
        _loading = false;
        _error = errorText(e);
      });
    }
  }

  void _goTo(String dir) {
    _query.clear();
    setState(() {
      _dir = dir;
      _searching = false;
    });
    _load();
  }

  void _up() {
    if (_dir != storageRoot) _goTo(p.dirname(_dir));
  }

  List<Entry> get _visible {
    final q = _query.text.trim().toLowerCase();
    if (q.isEmpty) return _entries;
    return _entries.where((e) => e.name.toLowerCase().contains(q)).toList();
  }

  Future<void> _open(Entry e) async {
    if (e.isDir) return _goTo(e.path);
    final files = _visible.where((x) => !x.isDir).map((x) => x.path).toList();
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ReaderScreen(paths: files, index: files.indexOf(e.path))),
    );
    if (mounted) _load();
  }

  Future<void> _onAction(String action, Entry e) async {
    switch (action) {
      case 'rename':
        if (await renameBook(context, e.path) != null) _load();
      case 'move':
        if (await moveBook(context, e.path) != null) _load();
      case 'delete':
        if (await deleteBook(context, e.path)) _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: _dir == storageRoot && !_searching,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_searching) {
          _query.clear();
          setState(() => _searching = false);
        } else {
          _up();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: _searching
              ? TextField(
                  controller: _query,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(hintText: 'Buscar en esta carpeta…', border: InputBorder.none),
                )
              : Text(_dir == storageRoot ? 'Mis libros' : p.basename(_dir), overflow: TextOverflow.ellipsis),
          leading: _dir != storageRoot && !_searching
              ? IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: _up)
              : null,
          actions: [
            IconButton(
              icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
              tooltip: 'Buscar',
              onPressed: () {
                _query.clear();
                setState(() => _searching = !_searching);
              },
            ),
            PopupMenuButton<SortMode>(
              icon: const Icon(Icons.sort_rounded),
              tooltip: 'Ordenar',
              initialValue: _sort,
              onSelected: (m) {
                _sort = m;
                _load();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: SortMode.name, child: Text('Nombre')),
                PopupMenuItem(value: SortMode.date, child: Text('Más recientes')),
                PopupMenuItem(value: SortMode.size, child: Text('Tamaño')),
              ],
            ),
          ],
        ),
        body: _body(cs),
      ),
    );
  }

  Widget _body(ColorScheme cs) {
    if (_access == null) return const Center(child: CircularProgressIndicator());
    if (_access == false) return _permissionView(cs);
    return Column(
      children: [
        _breadcrumb(cs),
        if (_dir == storageRoot) _shortcuts(),
        Expanded(child: _list(cs)),
      ],
    );
  }

  Widget _permissionView(ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_special_rounded, size: 72, color: cs.primary),
            const SizedBox(height: 20),
            Text('Necesito acceso a tus archivos', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Para listar, renombrar, mover y borrar tus libros activa “Acceso a todos los archivos”.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _requestAccess,
              icon: const Icon(Icons.lock_open_rounded),
              label: const Text('Conceder acceso'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _breadcrumb(ColorScheme cs) {
    final rel = _dir == storageRoot ? <String>[] : p.split(p.relative(_dir, from: storageRoot));
    Widget chip(String label, VoidCallback onTap, {bool last = false, IconData? icon}) => Padding(
          padding: const EdgeInsets.only(right: 4),
          child: ActionChip(
            avatar: icon != null ? Icon(icon, size: 16) : null,
            label: Text(label),
            onPressed: last ? null : onTap,
            side: BorderSide.none,
            backgroundColor: last ? cs.primaryContainer : cs.surfaceContainerHigh,
          ),
        );
    return SizedBox(
      height: 48,
      child: LayoutBuilder(
        builder: (_, c) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          reverse: true,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: c.maxWidth - 24),
            child: Row(
              children: [
                chip('Almacenamiento', () => _goTo(storageRoot), last: rel.isEmpty, icon: Icons.smartphone_rounded),
                for (var i = 0; i < rel.length; i++) ...[
                  Icon(Icons.chevron_right_rounded, size: 18, color: cs.onSurfaceVariant),
                  chip(
                    rel[i],
                    () => _goTo(p.joinAll([storageRoot, ...rel.sublist(0, i + 1)])),
                    last: i == rel.length - 1,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _shortcuts() {
    const names = ['Download', 'Documents', 'Books', 'Documentos'];
    final found = names.where((n) => Directory(p.join(storageRoot, n)).existsSync()).toList();
    if (found.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: 8,
          children: [
            for (final n in found)
              ActionChip(
                avatar: const Icon(Icons.bolt_rounded, size: 16),
                label: Text(n),
                onPressed: () => _goTo(p.join(storageRoot, n)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _list(ColorScheme cs) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final items = _visible;
    if (_error != null || items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 80),
            Icon(_error != null ? Icons.error_outline_rounded : Icons.auto_stories_outlined,
                size: 64, color: cs.outline),
            const SizedBox(height: 12),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  _error ?? (_query.text.isNotEmpty ? 'Sin resultados' : 'No hay libros ni carpetas aquí'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
            ),
          ],
        ),
      );
    }
    final folders = items.where((e) => e.isDir).length;
    final books = items.length - folders;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        itemCount: items.length + 1,
        itemBuilder: (_, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Text(
                '$books libros · $folders carpetas',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            );
          }
          final e = items[i - 1];
          return _EntryTile(entry: e, onTap: () => _open(e), onAction: (a) => _onAction(a, e));
        },
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  final Entry entry;
  final VoidCallback onTap;
  final void Function(String) onAction;
  const _EntryTile({required this.entry, required this.onTap, required this.onAction});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = entry.isDir ? cs.primary : extColor(entry.ext);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withAlpha(36),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: entry.isDir
                      ? Icon(Icons.folder_rounded, color: color)
                      : Text(
                          entry.ext.substring(1).toUpperCase(),
                          style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11),
                        ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(entry.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(
                        entry.isDir ? 'Carpeta' : '${formatSize(entry.size)} · ${formatDate(entry.modified)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (entry.isDir)
                  const Padding(padding: EdgeInsets.all(12), child: Icon(Icons.chevron_right_rounded))
                else
                  PopupMenuButton<String>(
                    onSelected: onAction,
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                          value: 'rename',
                          child: ListTile(leading: Icon(Icons.edit_rounded), title: Text('Renombrar'))),
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
          ),
        ),
      ),
    );
  }
}
