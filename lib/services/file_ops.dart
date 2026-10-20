import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

const storageRoot = '/storage/emulated/0';
const bookExtensions = {'.pdf', '.epub', '.docx', '.txt', '.md'};

enum SortMode { name, date, size }

class Entry {
  final FileSystemEntity entity;
  final bool isDir;
  final String name;
  final int size;
  final DateTime modified;

  Entry(this.entity, this.isDir, this.name, this.size, this.modified);

  String get path => entity.path;
  String get ext => p.extension(name).toLowerCase();
  String get title => isDir ? name : p.basenameWithoutExtension(name);
}

int naturalCompare(String a, String b) {
  final re = RegExp(r'(\d+)|(\D+)');
  final ma = re.allMatches(a.toLowerCase()).map((m) => m[0]!).toList();
  final mb = re.allMatches(b.toLowerCase()).map((m) => m[0]!).toList();
  for (var i = 0; i < ma.length && i < mb.length; i++) {
    final x = ma[i], y = mb[i];
    final nx = int.tryParse(x), ny = int.tryParse(y);
    final c = (nx != null && ny != null) ? nx.compareTo(ny) : x.compareTo(y);
    if (c != 0) return c;
  }
  return ma.length.compareTo(mb.length);
}

String formatSize(int b) {
  if (b < 1024) return '$b B';
  if (b < 1048576) return '${(b / 1024).toStringAsFixed(0)} KB';
  if (b < 1073741824) return '${(b / 1048576).toStringAsFixed(1)} MB';
  return '${(b / 1073741824).toStringAsFixed(2)} GB';
}

String formatDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

String errorText(Object e) {
  if (e is FileSystemException) {
    final os = e.osError?.message;
    final msg = e.message.isNotEmpty ? e.message : 'Error de archivo';
    return os != null && os.isNotEmpty ? '$msg ($os)' : msg;
  }
  return e.toString();
}

class FileOps {
  static Future<List<Entry>> list(String dir, SortMode sort) async {
    final out = <Entry>[];
    await for (final e in Directory(dir).list(followLinks: false)) {
      final name = p.basename(e.path);
      if (name.startsWith('.')) continue;
      final isDir = e is Directory;
      final isBook = e is File && bookExtensions.contains(p.extension(name).toLowerCase());
      if (!isDir && !isBook) continue;
      final st = await e.stat();
      out.add(Entry(e, isDir, name, st.size, st.modified));
    }
    out.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      switch (sort) {
        case SortMode.date:
          return b.modified.compareTo(a.modified);
        case SortMode.size:
          return b.size.compareTo(a.size);
        case SortMode.name:
          return naturalCompare(a.name, b.name);
      }
    });
    return out;
  }

  static String? validateName(String n) {
    final t = n.trim();
    if (t.isEmpty) return 'El nombre no puede estar vacío';
    if (t.contains('/') || t.contains('\u0000')) return 'No se permite el carácter “/”';
    if (t == '.' || t == '..') return 'Nombre no válido';
    if (utf8.encode(t).length > 240) return 'Nombre demasiado largo';
    return null;
  }

  static Future<String> rename(String path, String newBase) async {
    final err = validateName(newBase);
    if (err != null) throw FileSystemException(err);
    final target = p.join(p.dirname(path), newBase.trim() + p.extension(path));
    if (target == path) return path;
    if (await File(target).exists()) {
      throw const FileSystemException('Ya existe un archivo con ese nombre');
    }
    await File(path).rename(target);
    return target;
  }

  static Future<String> _unique(String target) async {
    if (!await File(target).exists()) return target;
    final dir = p.dirname(target);
    final base = p.basenameWithoutExtension(target);
    final ext = p.extension(target);
    var i = 1;
    while (await File(p.join(dir, '$base ($i)$ext')).exists()) {
      i++;
    }
    return p.join(dir, '$base ($i)$ext');
  }

  static Future<String> move(String path, String destDir) async {
    if (p.equals(p.dirname(path), destDir)) {
      throw const FileSystemException('El libro ya está en esa carpeta');
    }
    final target = await _unique(p.join(destDir, p.basename(path)));
    final f = File(path);
    try {
      await f.rename(target);
    } on FileSystemException {
      await f.copy(target);
      await f.delete();
    }
    return target;
  }

  static Future<void> delete(String path) => File(path).delete();
}
