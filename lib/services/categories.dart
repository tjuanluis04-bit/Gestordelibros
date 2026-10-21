import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class Category {
  String name;
  List<String> folders;

  Category(this.name, [List<String>? folders]) : folders = folders ?? [];

  Map<String, dynamic> toJson() => {'name': name, 'folders': folders};

  factory Category.fromJson(Map<String, dynamic> j) =>
      Category(j['name'] as String, (j['folders'] as List).cast<String>().toList());
}

class CategoryStore {
  static const _key = 'move_categories_v1';

  static Future<List<Category>> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_key);
      if (raw == null) return [];
      return (jsonDecode(raw) as List)
          .map((e) => Category.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<Category> cats) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_key, jsonEncode(cats.map((c) => c.toJson()).toList()));
  }
}
