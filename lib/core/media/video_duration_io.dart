import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

/// Length of [file], or null when it cannot be read.
Future<Duration?> readVideoDuration(XFile file) async {
  final controller = VideoPlayerController.file(File(file.path));
  try {
    await controller.initialize().timeout(const Duration(seconds: 15));
    final duration = controller.value.duration;
    return duration > Duration.zero ? duration : null;
  } catch (_) {
    return null;
  } finally {
    await controller.dispose();
  }
}
