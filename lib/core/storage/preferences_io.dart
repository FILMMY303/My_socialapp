import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

final _values = <String, String>{};
File? _file;

/// Reads saved settings from disk. Missing or broken files start empty.
Future<void> loadPreferences() async {
  try {
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, 'preferences.json'));
    _file = file;
    if (await file.exists()) {
      final data = jsonDecode(await file.readAsString()) as Map;
      _values.addAll({for (final e in data.entries) '${e.key}': '${e.value}'});
    }
  } catch (_) {
    // Settings then only last for this session.
  }
}

String? readPreference(String key) => _values[key];

void writePreference(String key, String value) {
  _values[key] = value;
  final file = _file;
  if (file == null) return;
  file
      .create(recursive: true)
      .then((f) => f.writeAsString(jsonEncode(_values), flush: true))
      .catchError((Object _) => file);
}
