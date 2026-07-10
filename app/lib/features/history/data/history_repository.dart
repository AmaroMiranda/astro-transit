/// Local persistence for history entries (RF-028), backed by SharedPreferences.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/history_entry.dart';

class HistoryRepository {
  static const _key = 'astrotransit.history';

  Future<List<HistoryEntry>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    return raw
        .map((s) => HistoryEntry.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => b.dateTimeUtc.compareTo(a.dateTimeUtc));
  }

  Future<void> add(HistoryEntry entry) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    raw.add(jsonEncode(entry.toJson()));
    await prefs.setStringList(_key, raw);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
