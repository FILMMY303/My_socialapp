import 'dart:async';

import 'package:image_picker/image_picker.dart';
import 'package:web/web.dart' as web;

/// Length of [file], or null when the browser cannot read it.
///
/// On the web, a picked file's path is a blob URL, so a detached <video>
/// element can load just its metadata.
Future<Duration?> readVideoDuration(XFile file) async {
  final video = web.HTMLVideoElement()
    ..preload = 'metadata'
    ..muted = true;
  try {
    final loaded = Future.any([
      web.EventStreamProviders.loadedMetadataEvent.forTarget(video).first,
      web.EventStreamProviders.errorEvent
          .forTarget(video)
          .first
          .then((_) => throw StateError('unreadable video')),
    ]);
    video.src = file.path;
    await loaded.timeout(const Duration(seconds: 15));

    var seconds = video.duration;
    if (seconds.isInfinite) {
      // Recorded WebM files often have no duration in their header. Seeking
      // far past the end makes the browser scan the file and report it.
      final changed = web.EventStreamProviders.durationChangeEvent
          .forTarget(video)
          .firstWhere((_) => video.duration.isFinite);
      video.currentTime = 1e101;
      await changed.timeout(const Duration(seconds: 15));
      seconds = video.duration;
    }
    if (seconds.isNaN || seconds.isInfinite || seconds <= 0) return null;
    return Duration(milliseconds: (seconds * 1000).round());
  } catch (_) {
    return null;
  } finally {
    video
      ..removeAttribute('src')
      ..load();
  }
}
