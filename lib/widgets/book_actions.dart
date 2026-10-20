import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../services/file_ops.dart';

void _snack(BuildContext context, String msg, {bool error = false}) {
  final cs = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg, style: error ? TextStyle(color: cs.onError) : null),
      backgroundColor: error ? cs.error : null,
    ));
}

/// Devuelve la nueva ruta o null si no hubo cambios.
Future<String?> renameBook(BuildContext context, String path) async {
  final base = p.basenameWithoutExtension(path);
  final result = await showDialog<String>(
    context: context,
    builder: (_) => _RenameDialog(initial: base, ext: p.extension(path)),
  );
  if (result == null || result.trim() == base || !context.mounted) return null;
  try {
    final np = await FileOps.rename(path, result);
    if (context.mounted) _snack(context, 'Renombrado');
    return np;
  } catch (e) {
    if (context.mounted) _snack(context, errorText(e), error: true);
    return null;
  }
}

/// Devuelve la nueva ruta o null si se canceló / falló.
Future<String?> moveBook(BuildContext context, String path) async {
  final dest = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _FolderPicker(start: p.dirname(path)),
  );
  if (dest == null || !context.mounted) return null;
  try {
    final np = await FileOps.move(path, dest);
    if (context.mounted) {
      _snack(context, 'Movido a ${dest == storageRoot ? 'Almacenamiento interno' : p.basename(dest)}');
    }
    return np;
  } catch (e) {
    if (context.mounted) _snack(context, errorText(e), error: true);
    return null;
  }
}

Future<bool> deleteBook(BuildContext context, String path) async {
  final cs = Theme.of(context).colorScheme;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(Icons.delete_outline_rounded, color: cs.error, size: 32),
      title: const Text('¿Eliminar libro?'),
      content: Text('“${p.basenameWithoutExtension(path)}” se borrará de forma permanente.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: cs.error, foregroundColor: cs.onError),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Eliminar'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;
  try {
    await FileOps.delete(path);
    if (context.mounted) _snack(context, 'Libro eliminado');
    return true;
  } catch (e) {
    if (context.mounted) _snack(context, errorText(e), error: true);
    return false;
  }
}

// ───────────────────────── Renombrar ─────────────────────────

const _symbols = [
  '📚', '📖', '⭐', '❤️', '🔥', '✅', '📝', '🔖', '✨', '🎓', '💡', '🌙',
  '★', '♥', '•', '—', '·', '(', ')', '[', ']', '#', '&', '+',
];

class _RenameDialog extends StatefulWidget {
  final String initial;
  final String ext;
  const _RenameDialog({required this.initial, required this.ext});

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _c = TextEditingController(text: widget.initial)
    ..selection = TextSelection.collapsed(offset: widget.initial.length);

  String? get _error => _c.text.isEmpty ? null : FileOps.validateName(_c.text);
  bool get _canSave =>
      _c.text.trim().isNotEmpty && _error == null && _c.text.trim() != widget.initial;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _insert(String s) {
    final sel = _c.selection;
    final start = sel.isValid ? sel.start : _c.text.length;
    final end = sel.isValid ? sel.end : _c.text.length;
    _c.value = TextEditingValue(
      text: _c.text.replaceRange(start, end, s),
      selection: TextSelection.collapsed(offset: start + s.length),
    );
    setState(() {});
  }

  void _save() => Navigator.pop(context, _c.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Renombrar'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _c,
              autofocus: true,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (_canSave) _save();
              },
              decoration: InputDecoration(
                labelText: 'Nombre',
                suffixText: widget.ext,
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Text('Emojis y símbolos', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 8),
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _symbols.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, i) => ActionChip(
                  label: Text(_symbols[i], style: const TextStyle(fontSize: 18)),
                  onPressed: () => _insert(_symbols[i]),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _canSave ? _save : null, child: const Text('Guardar')),
      ],
    );
  }
}

// ───────────────────────── Selector de carpeta ─────────────────────────

class _FolderPicker extends StatefulWidget {
  final String start;
  const _FolderPicker({required this.start});

  @override
  State<_FolderPicker> createState() => _FolderPickerState();
}

class _FolderPickerState extends State<_FolderPicker> {
  late String _dir = widget.start;
  List<Directory> _dirs = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = <Directory>[];
      await for (final e in Directory(_dir).list(followLinks: false)) {
        if (e is Directory && !p.basename(e.path).startsWith('.')) r.add(e);
      }
      r.sort((a, b) => naturalCompare(p.basename(a.path), p.basename(b.path)));
      if (mounted) setState(() {
        _dirs = r;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() {
        _dirs = [];
        _error = errorText(e);
      });
    }
  }

  void _goTo(String dir) {
    setState(() => _dir = dir);
    _load();
  }

  Future<void> _newFolder() async {
    final name = await showDialog<String>(context: context, builder: (_) => const _NewFolderDialog());
    if (name == null || !mounted) return;
    try {
      final d = Directory(p.join(_dir, name));
      await d.create();
      _goTo(d.path);
    } catch (e) {
      if (mounted) _snack(context, errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final shown = _dir == storageRoot ? 'Almacenamiento interno' : p.relative(_dir, from: storageRoot);
    return SizedBox(
      height: MediaQuery.of(context).size.height * .78,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Mover a…', style: Theme.of(context).textTheme.titleLarge),
            ),
          ),
          ListTile(
            dense: true,
            leading: Icon(Icons.folder_open_rounded, color: cs.primary),
            title: Text(shown, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              children: [
                if (_dir != storageRoot)
                  ListTile(
                    leading: const Icon(Icons.arrow_upward_rounded),
                    title: const Text('Subir un nivel'),
                    onTap: () => _goTo(p.dirname(_dir)),
                  ),
                for (final d in _dirs)
                  ListTile(
                    leading: Icon(Icons.folder_rounded, color: cs.primary),
                    title: Text(p.basename(d.path), maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _goTo(d.path),
                  ),
                if (_dirs.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Text(_error ?? 'Sin subcarpetas', style: TextStyle(color: cs.onSurfaceVariant)),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 16, 12),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: _newFolder,
                  icon: const Icon(Icons.create_new_folder_outlined),
                  label: const Text('Nueva'),
                ),
                const Spacer(),
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
                const SizedBox(width: 8),
                FilledButton(onPressed: () => Navigator.pop(context, _dir), child: const Text('Mover aquí')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NewFolderDialog extends StatefulWidget {
  const _NewFolderDialog();

  @override
  State<_NewFolderDialog> createState() => _NewFolderDialogState();
}

class _NewFolderDialogState extends State<_NewFolderDialog> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final err = _c.text.isEmpty ? null : FileOps.validateName(_c.text);
    return AlertDialog(
      title: const Text('Nueva carpeta'),
      content: TextField(
        controller: _c,
        autofocus: true,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(labelText: 'Nombre', errorText: err, border: const OutlineInputBorder()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _c.text.trim().isNotEmpty && err == null ? () => Navigator.pop(context, _c.text.trim()) : null,
          child: const Text('Crear'),
        ),
      ],
    );
  }
}
