import 'package:web/web.dart' as web;

/// localStorage is synchronous; nothing to load.
Future<void> loadPreferences() async {}

// Storage can be blocked (private mode, disabled site data); settings then
// only last for this session.
String? readPreference(String key) {
  try {
    return web.window.localStorage.getItem(key);
  } catch (_) {
    return null;
  }
}

void writePreference(String key, String value) {
  try {
    web.window.localStorage.setItem(key, value);
  } catch (_) {}
}
