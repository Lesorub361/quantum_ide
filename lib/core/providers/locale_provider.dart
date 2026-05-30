import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';

class LocaleNotifier extends StateNotifier<Locale> {
  LocaleNotifier() : super(const Locale('en')) {
    _loadLocale();
  }

  static const _keyLocale = 'app_locale';

  Future<void> _loadLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final langCode = prefs.getString(_keyLocale);
    if (langCode != null) {
      state = Locale(langCode);
    }
  }

  Future<void> setLocale(Locale locale) async {
    state = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLocale, locale.languageCode);
  }

  Future<void> toggleLocale() async {
    if (state.languageCode == 'en') {
      await setLocale(const Locale('ru'));
    } else {
      await setLocale(const Locale('en'));
    }
  }
}

final localeProvider = StateNotifierProvider<LocaleNotifier, Locale>((ref) {
  return LocaleNotifier();
});

final localizationsProvider = Provider<AppLocalizations>((ref) {
  final locale = ref.watch(localeProvider);
  return lookupAppLocalizations(locale);
});

