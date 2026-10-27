/// Small key/value settings: localStorage in the browser, a JSON file in the
/// app's support folder on phones and desktop. Call [loadPreferences] once
/// before reading.
library;

export 'preferences_io.dart'
    if (dart.library.js_interop) 'preferences_web.dart';
