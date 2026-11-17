import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Choices that belong to this phone, not to the account: light or dark mode. Kept in ordinary app preferences
/// (nothing personal is stored here).
class AppSettings extends ChangeNotifier {
  AppSettings({SharedPreferencesAsync? prefs}) : _prefs = prefs;

  static const _themeKey = 'theme_mode';
  SharedPreferencesAsync? _prefs;

  ThemeMode themeMode = ThemeMode.system;

  SharedPreferencesAsync get _store => _prefs ??= SharedPreferencesAsync();

  Future<void> load() async {
    try {
      final saved = await _store.getString(_themeKey);
      themeMode = ThemeMode.values.firstWhere((m) => m.name == saved, orElse: () => ThemeMode.system);
      notifyListeners();
    } catch (_) {
      // first run, or preferences unavailable (tests): keep following the phone
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == themeMode) return;
    themeMode = mode;
    notifyListeners();
    try {
      await _store.setString(_themeKey, mode.name);
    } catch (_) {}
  }

  /// The moon/sun button on the home screen: switch to the opposite of what is showing now.
  Future<void> toggle(Brightness showing) =>
      setThemeMode(showing == Brightness.dark ? ThemeMode.light : ThemeMode.dark);
}
