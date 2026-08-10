import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'settings_model.dart';

class SettingsRepository {
  static const _key = 'dupora_settings_v1';

  Future<DuporaSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return const DuporaSettings();
    try {
      return DuporaSettings.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } catch (_) {
      return const DuporaSettings();
    }
  }

  Future<void> save(DuporaSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(settings.toJson()));
  }
}
