/// Reads the length of a picked video file.
library;

export 'video_duration_io.dart'
    if (dart.library.js_interop) 'video_duration_web.dart';
