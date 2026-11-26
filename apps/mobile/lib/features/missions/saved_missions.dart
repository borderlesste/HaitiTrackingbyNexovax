import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Misiones guardadas "para después" en este teléfono.
class SavedMissions {
  static final ids = ValueNotifier<Set<String>>(<String>{});
  static const _key = 'saved_missions_v1';
  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    ids.value = (prefs.getStringList(_key) ?? const <String>[]).toSet();
    _loaded = true;
  }

  static bool isSaved(String id) => ids.value.contains(id);

  static Future<void> toggle(String id) async {
    final next = {...ids.value};
    if (!next.remove(id)) next.add(id);
    ids.value = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, next.toList());
  }
}
