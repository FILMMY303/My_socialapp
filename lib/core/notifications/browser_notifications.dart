/// System notifications through the browser (web only; a no-op elsewhere).
library;

export 'browser_notifications_stub.dart'
    if (dart.library.js_interop) 'browser_notifications_web.dart';
