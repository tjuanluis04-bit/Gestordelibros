import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../services/categories.dart';
import '../services/file_ops.dart';

/// Devuelve la carpeta destino elegida, o null si se cancela.
Future<String?> showMoveSheet(BuildContext context, {required String filePath}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => MoveSheet(filePath: filePath),
  );
}

class _Sub {
  final String path;
  final bool hasSub;
  _Sub(this.path, this.hasSub);
}

enum _Mode { home, browse, pick }

class MoveSheet extends StatefulWidget {
  final String filePath;
  const MoveSheet({super.key, required this.filePath});

  @override
  State<MoveSheet> createState() => _MoveSheetState();
}

class _MoveSheetState extends State<MoveSheet> {
  List<Category> _cats = [];
  bool _ready = false;
  bool _editing = false;
  String? _notice;
  _Mode _mode = _Mode.home;
  String _dir = storageRoot;
  String _root = storageRoot;
  Category? _pickFor;
  List<_Sub> _subs = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    CategoryStore.load().then((c) {
      if (mounted) setState(() {
        _cats = c;
        _ready = true;
      });
    });
  }

  Future<void> _persist() => CategoryStore.save(_cats);

  Future<void> _loadSubs() async {
    setState(() => _loading = true);
    try {
      final dirs = await FileOps.subdirs(_dir);
      final subs = await Future.wait(dirs.map((d) async => _Sub(d.path, await FileOps.hasSubdirs(d.path))));
      if (!mounted) return;
      setState(() {
        _subs = subs;
        _loading = false;
        _notice = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _subs = [];
        _loading = false;
        _notice = errorText(e);
      });
    }
  }

  void _startBrowse(String dir, String root, {_Mode mode = _Mode.browse}) {
    setState(() {
      _mode = mode;
      _dir = dir;
      _root = root;
      _notice = null;
    });
    _loadSubs();
  }

  void _enter(String path) {
    setState(() => _dir = path);
    _loadSubs();
  }

  void _back() {
    if (p.equals(_dir, _root)) {
      setState(() {
        _mode = _Mode.home;
        _pickFor = null;
        _notice = null;
      });
    } else {
      _enter(p.dirname(_dir));
    }
  }

  /// Carpeta de una categoría: sin subcarpetas → mover directo; con subcarpetas → entrar.
  Future<void> _openFolder(String path) async {
    if (!await Directory(path).exists()) {
      if (mounted) setState(() => _notice = 'La carpeta ya no existe: ${p.basename(path)}');
      return;
    }
    final hasSub = await FileOps.hasSubdirs(path);
    if (!mounted) return;
    if (!hasSub) {
      Navigator.pop(context, path);
      return;
    }
    _startBrowse(path, path);
  }

  void _tapSub(_Sub s) {
    if (_mode == _Mode.pick || s.hasSub) {
      _enter(s.path);
    } else {
      Navigator.pop(context, s.path);
    }
  }

  void _explore() {
    final start = p.isWithin(storageRoot, widget.filePath) ? p.dirname(widget.filePath) : storageRoot;
    _startBrowse(start, storageRoot);
  }

  Future<void> _newFolderHere() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _PromptDialog(
        title: 'Nueva carpeta',
        label: 'Nombre',
        action: 'Crear y mover',
        fileName: true,
      ),
    );
    if (name == null || !mounted) return;
    try {
      final d = Directory(p.join(_dir, name));
      await d.create();
      if (mounted) Navigator.pop(context, d.path);
    } catch (e) {
      if (mounted) setState(() => _notice = errorText(e));
    }
  }

  // ── categorías ──
  Future<void> _newCategory() async {
    final n = await showDialog<String>(
      context: context,
      builder: (_) => const _PromptDialog(title: 'Nueva categoría', label: 'Nombre (ej. Novelas)', action: 'Crear'),
    );
    if (n == null || !mounted) return;
    setState(() => _cats.add(Category(n)));
    await _persist();
  }

  Future<void> _renameCategory(Category c) async {
    final n = await showDialog<String>(
      context: context,
      builder: (_) => _PromptDialog(title: 'Renombrar categoría', label: 'Nombre', action: 'Guardar', initial: c.name),
    );
    if (n == null || !mounted) return;
    setState(() => c.name = n);
    await _persist();
  }

  Future<void> _deleteCategory(Category c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('¿Eliminar “${c.name}”?'),
        content: const Text('Solo se elimina la categoría; las carpetas no se tocan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _cats.remove(c));
    await _persist();
  }

  Future<void> _removeFolder(Category c, String f) async {
    setState(() => c.folders.remove(f));
    await _persist();
  }

  void _addFolderTo(Category c) {
    _pickFor = c;
    _startBrowse(storageRoot, storageRoot, mode: _Mode.pick);
  }

  Future<void> _confirmPick() async {
    final c = _pickFor;
    if (c == null) return;
    if (!c.folders.contains(_dir)) c.folders.add(_dir);
    await _persist();
    if (!mounted) return;
    setState(() {
      _mode = _Mode.home;
      _pickFor = null;
    });
  }

  // ── UI ──
  String _shown(String d) => p.equals(d, storageRoot) ? 'Almacenamiento interno' : p.relative(d, from: storageRoot);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * .85,
      child: _mode == _Mode.home ? _home(context) : _browse(context),
    );
  }

  Widget _banner(ColorScheme cs) => _notice == null
      ? const SizedBox.shrink()
      : Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(12)),
          child: Text(_notice!, style: TextStyle(color: cs.onErrorContainer)),
        );

  Widget _home(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Mover a…', style: tt.titleLarge),
                    Text(p.basenameWithoutExtension(widget.filePath),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
              IconButton.filledTonal(
                icon: Icon(_editing ? Icons.check_rounded : Icons.tune_rounded),
                tooltip: _editing ? 'Listo' : 'Gestionar categorías',
                onPressed: () => setState(() => _editing = !_editing),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: !_ready
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _banner(cs),
                    if (_cats.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(16)),
                        child: Text(
                          'Crea categorías (por ejemplo “Novelas” o “Estudio”) y asígnales carpetas para mover tus libros con un toque. Pulsa el botón de ajustes de arriba para empezar.',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ),
                    for (final c in _cats) _catBlock(c, cs, tt),
                  ],
                ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _explore,
                  icon: const Icon(Icons.folder_open_rounded),
                  label: const Text('Explorar'),
                ),
              ),
              if (_editing) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _newCategory,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Categoría'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _catBlock(Category c, ColorScheme cs, TextTheme tt) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.label_rounded, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(c.name, style: tt.titleSmall)),
              if (_editing) ...[
                IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.edit_rounded, size: 20),
                    onPressed: () => _renameCategory(c)),
                IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.delete_outline_rounded, size: 20, color: cs.error),
                    onPressed: () => _deleteCategory(c)),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final f in c.folders)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: _editing
                      ? InputChip(
                          avatar: const Icon(Icons.folder_rounded, size: 18),
                          label: Text(p.basename(f), overflow: TextOverflow.ellipsis),
                          onDeleted: () => _removeFolder(c, f),
                        )
                      : ActionChip(
                          avatar: Icon(Icons.folder_rounded, size: 18, color: cs.primary),
                          label: Text(p.basename(f), overflow: TextOverflow.ellipsis),
                          onPressed: () => _openFolder(f),
                        ),
                ),
              if (_editing)
                ActionChip(
                  avatar: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Carpeta'),
                  onPressed: () => _addFolderTo(c),
                ),
            ],
          ),
          if (c.folders.isEmpty && !_editing)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Sin carpetas todavía', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ),
        ],
      ),
    );
  }

  Widget _browse(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final picking = _mode == _Mode.pick;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 16, 8),
          child: Row(
            children: [
              IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: _back),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(picking ? 'Elegir carpeta para “${_pickFor?.name ?? ''}”' : 'Mover a…',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.titleMedium),
                    Text(_shown(_dir),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  children: [
                    if (_notice != null) Padding(padding: const EdgeInsets.all(16), child: _banner(cs)),
                    if (_subs.isEmpty && _notice == null)
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Center(
                          child: Text('Esta carpeta no tiene subcarpetas', style: TextStyle(color: cs.onSurfaceVariant)),
                        ),
                      ),
                    for (final s in _subs)
                      ListTile(
                        leading: Icon(Icons.folder_rounded, color: cs.primary),
                        title: Text(p.basename(s.path), maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: (!picking && !s.hasSub) ? const Text('Sin subcarpetas · mover aquí directamente') : null,
                        trailing: (picking || s.hasSub)
                            ? const Icon(Icons.chevron_right_rounded)
                            : Icon(Icons.drive_file_move_rounded, color: cs.primary),
                        onTap: () => _tapSub(s),
                      ),
                  ],
                ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 16, 12),
          child: picking
              ? Row(
                  children: [
                    TextButton(
                      onPressed: () => setState(() {
                        _mode = _Mode.home;
                        _pickFor = null;
                      }),
                      child: const Text('Cancelar'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: p.equals(_dir, storageRoot) ? null : _confirmPick,
                      child: const Text('Añadir esta carpeta'),
                    ),
                  ],
                )
              : Row(
                  children: [
                    TextButton.icon(
                      onPressed: _newFolderHere,
                      icon: const Icon(Icons.create_new_folder_outlined),
                      label: const Text('Nueva'),
                    ),
                    const Spacer(),
                    FilledButton(onPressed: () => Navigator.pop(context, _dir), child: const Text('Mover aquí')),
                  ],
                ),
        ),
      ],
    );
  }
}

class _PromptDialog extends StatefulWidget {
  final String title, label, action, initial;
  final bool fileName;
  const _PromptDialog({
    required this.title,
    required this.label,
    required this.action,
    this.initial = '',
    this.fileName = false,
  });

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  late final TextEditingController _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  String? get _err => (_c.text.isEmpty || !widget.fileName) ? null : FileOps.validateName(_c.text);
  bool get _ok => _c.text.trim().isNotEmpty && _err == null;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _c,
        autofocus: true,
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) {
          if (_ok) Navigator.pop(context, _c.text.trim());
        },
        decoration: InputDecoration(labelText: widget.label, errorText: _err, border: const OutlineInputBorder()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _ok ? () => Navigator.pop(context, _c.text.trim()) : null, child: Text(widget.action)),
      ],
    );
  }
}
