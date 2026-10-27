import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/errors/app_exception.dart';
import '../../core/media/video_duration.dart';
import '../models/models.dart';

/// Picks and uploads images/videos to Supabase Storage (online only).
///
/// Paths always start with the uploader's id, which the storage policies
/// require: `<user>/<file>` or, for chat, `<sender>/<receiver>/<file>`.
class MediaService {
  MediaService(this._client, this._userId);

  static const maxImageBytes = 5 * 1024 * 1024;
  static const maxVideoBytes = 50 * 1024 * 1024;
  static const maxVideoDuration = Duration(minutes: 2);

  final SupabaseClient _client;
  final String _userId;
  final _picker = ImagePicker();
  final _uuid = const Uuid();
  final _signedUrls = <String, (String, DateTime)>{};

  /// Lets the user choose an image or a video of at most [maxVideoDuration].
  /// Returns null when cancelled.
  Future<XFile?> pick(MediaType type) async {
    final XFile? file;
    try {
      file = type == MediaType.image
          ? await _picker.pickImage(
              source: ImageSource.gallery,
              maxWidth: 2048,
              imageQuality: 85,
            )
          : await _picker.pickVideo(
              source: ImageSource.gallery,
              // Only limits camera recordings, not gallery files or the web,
              // so the length is checked below as well.
              maxDuration: maxVideoDuration,
            );
    } catch (error) {
      throw AppException('Could not open the file picker: $error');
    }
    if (file != null && type == MediaType.video) {
      checkVideoDuration(await readVideoDuration(file));
    }
    return file;
  }

  /// Throws a [ValidationException] unless [duration] is known and at most
  /// [maxVideoDuration].
  static void checkVideoDuration(Duration? duration) {
    if (duration == null) {
      throw const ValidationException(
        'Could not read the length of this video. Try an MP4 or WebM file.',
      );
    }
    if (duration > maxVideoDuration) {
      throw ValidationException(
        'Videos must be 2 minutes or shorter. '
        'This one is ${formatDuration(duration)}.',
      );
    }
  }

  /// `m:ss`, e.g. 3:05.
  static String formatDuration(Duration duration) {
    final seconds = duration.inSeconds;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  Future<MediaRef> uploadPostMedia(XFile file, MediaType type) async {
    final path = await _upload(
      'post-media',
      '$_userId/${_name(file)}',
      file,
      type,
    );
    return MediaRef(
      url: _client.storage.from('post-media').getPublicUrl(path),
      type: type,
    );
  }

  Future<String> uploadAvatar(XFile file) async {
    final path = await _upload(
      'avatars',
      '$_userId/${_name(file)}',
      file,
      MediaType.image,
    );
    return _client.storage.from('avatars').getPublicUrl(path);
  }

  /// Chat media is private; the returned [MediaRef.url] is a storage path.
  Future<MediaRef> uploadChatMedia(
    XFile file,
    MediaType type,
    String partnerId,
  ) async {
    final path = await _upload(
      'chat-media',
      '$_userId/$partnerId/${_name(file)}',
      file,
      type,
    );
    return MediaRef(url: path, type: type);
  }

  /// Temporary URL for a private chat file, cached until shortly before it
  /// expires.
  Future<String> chatMediaUrl(String path) async {
    final cached = _signedUrls[path];
    if (cached != null && cached.$2.isAfter(DateTime.now())) return cached.$1;
    final url = await runOnline(
      () => _client.storage.from('chat-media').createSignedUrl(path, 3600),
    );
    _signedUrls[path] = (url, DateTime.now().add(const Duration(minutes: 55)));
    return url;
  }

  /// Best-effort removal of an uploaded public file (e.g. a cancelled post).
  Future<void> deletePublicFile(String bucket, String publicUrl) async {
    final marker = '/object/public/$bucket/';
    final index = publicUrl.indexOf(marker);
    if (index < 0) return;
    final path = Uri.decodeComponent(
      publicUrl.substring(index + marker.length),
    );
    try {
      await _client.storage.from(bucket).remove([path]);
    } catch (_) {
      // Leftover files are harmless; never fail the user action for this.
    }
  }

  Future<String> _upload(
    String bucket,
    String path,
    XFile file,
    MediaType type,
  ) async {
    final size = await file.length();
    final limit = type == MediaType.image ? maxImageBytes : maxVideoBytes;
    if (size > limit) {
      throw ValidationException(
        type == MediaType.image
            ? 'Images must be 5 MB or smaller.'
            : 'Videos must be 50 MB or smaller.',
      );
    }
    final contentType = _contentType(file, type);
    final bytes = await file.readAsBytes();
    return runOnline(
      () => _client.storage
          .from(bucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: contentType, upsert: false),
          )
          .then((_) => path),
      // Large videos need longer than a normal request.
      timeout: const Duration(minutes: 3),
    );
  }

  String _name(XFile file) {
    final dot = file.name.lastIndexOf('.');
    final ext = dot >= 0 ? file.name.substring(dot + 1).toLowerCase() : '';
    return ext.isEmpty ? _uuid.v4() : '${_uuid.v4()}.$ext';
  }

  String _contentType(XFile file, MediaType type) {
    final mime = file.mimeType;
    if (mime != null && mime.isNotEmpty) return mime;
    final name = file.name.toLowerCase();
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    if (name.endsWith('.gif')) return 'image/gif';
    if (name.endsWith('.webm')) return 'video/webm';
    if (name.endsWith('.mov')) return 'video/quicktime';
    if (name.endsWith('.mp4')) return 'video/mp4';
    return type == MediaType.image ? 'image/jpeg' : 'video/mp4';
  }
}
