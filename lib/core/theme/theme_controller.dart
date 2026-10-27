import 'package:flutter/material.dart';

import '../storage/preferences.dart';

/// Light / dark mode for the whole app, remembered across visits.
/// Starts in light mode until the user picks dark in settings.
class ThemeController extends ValueNotifier<ThemeMode>
    with WidgetsBindingObserver {
  ThemeController._() : super(_load()) {
    WidgetsBinding.instance.addObserver(this);
  }

  static final instance = ThemeController._();

  static const _key = 'theme_mode';

  static ThemeMode _load() =>
      ThemeMode.values.asNameMap()[readPreference(_key)] ?? ThemeMode.light;

  /// The mode actually shown; [ThemeMode.system] follows the browser setting.
  bool get isDark => switch (value) {
    ThemeMode.dark => true,
    ThemeMode.light => false,
    ThemeMode.system =>
      WidgetsBinding.instance.platformDispatcher.platformBrightness ==
          Brightness.dark,
  };

  void toggle() => setMode(isDark ? ThemeMode.light : ThemeMode.dark);

  void setMode(ThemeMode mode) {
    if (mode == value) return;
    value = mode;
    writePreference(_key, mode.name);
    rebuildAll();
  }

  /// In system mode, follow the browser when it switches light/dark.
  @override
  void didChangePlatformBrightness() {
    if (value == ThemeMode.system) rebuildAll();
  }

  /// Rebuilds every widget so the app colors (read in build methods, not
  /// from [Theme]) pick up the new palette without losing any state.
  static void rebuildAll() {
    void rebuild(Element element) {
      element.markNeedsBuild();
      element.visitChildren(rebuild);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(rebuild);
  }
}
