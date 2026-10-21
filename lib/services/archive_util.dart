import 'package:archive/archive.dart';

/// Lee los bytes de un archivo del zip (compatible con archive 3.x y 4.x).
List<int> archiveBytes(ArchiveFile f) {
  final d = f as dynamic;
  try {
    final c = d.content;
    if (c is List<int>) return c;
  } catch (_) {}
  return (d.readBytes() as List).cast<int>();
}
