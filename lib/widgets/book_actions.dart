import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../services/file_ops.dart';
import 'move_sheet.dart';

void showSnack(BuildContext context, String msg, {bool error = false}) {
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
    if (context.mounted) showSnack(context, 'Renombrado');
    return np;
  } catch (e) {
    if (context.mounted) showSnack(context, errorText(e), error: true);
    return null;
  }
}

/// Devuelve la nueva ruta o null si se canceló / falló.
Future<String?> moveBook(BuildContext context, String path) async {
  final dest = await showMoveSheet(context, filePath: path);
  if (dest == null || !context.mounted) return null;
  try {
    final np = await FileOps.move(path, dest);
    if (context.mounted) {
      showSnack(context, 'Movido a ${dest == storageRoot ? 'Almacenamiento interno' : p.basename(dest)}');
    }
    return np;
  } catch (e) {
    if (context.mounted) showSnack(context, errorText(e), error: true);
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
    if (context.mounted) showSnack(context, 'Libro eliminado');
    return true;
  } catch (e) {
    if (context.mounted) showSnack(context, errorText(e), error: true);
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

