import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// An error with a message that is safe to show to the user.
class AppException implements Exception {
  const AppException(this.message, {this.isTransient = false, this.cause});

  /// Converts any error thrown by Supabase, the network or the local database
  /// into an [AppException] with a readable message.
  factory AppException.from(Object error) {
    if (error is AppException) return error;

    if (error is PostgrestException) {
      final transient = _isTransientPostgrest(error);
      return AppException(
        transient ? _offlineMessage : _postgrestMessage(error),
        isTransient: transient,
        cause: error,
      );
    }

    if (error is StorageException) {
      final status = int.tryParse(error.statusCode ?? '');
      if (status != null && status >= 500) {
        return AppException(_offlineMessage, isTransient: true, cause: error);
      }
      final text = error.message.toLowerCase();
      final message = status == 413 || text.contains('size')
          ? 'The file is too large (images up to 5 MB, videos up to 50 MB).'
          : status == 415 || text.contains('mime')
          ? 'This file type is not supported. Use JPG, PNG, WebP, GIF, MP4 '
                'or WebM.'
          : status == 403 || text.contains('policy')
          ? "You don't have permission to upload here."
          : text.contains('bucket not found')
          ? 'Storage is not set up. Apply the latest Supabase migrations.'
          : 'Upload failed: ${error.message}';
      return AppException(message, cause: error);
    }

    if (error is AuthRetryableFetchException) {
      return AppException(_offlineMessage, isTransient: true, cause: error);
    }
    if (error is AuthException) {
      return AppException(error.message, cause: error);
    }

    // Network failures (ClientException, SocketException, TimeoutException,
    // ...) are not typed the same way on every platform, so anything else is
    // treated as a connectivity problem and retried later.
    return AppException(_offlineMessage, isTransient: true, cause: error);
  }

  final String message;

  /// True when retrying later may succeed (offline, timeout, server busy).
  final bool isTransient;

  final Object? cause;

  static const _offlineMessage =
      'Cannot reach the server. Check your internet connection and try again.';

  static bool _isTransientPostgrest(PostgrestException error) {
    final code = error.code ?? '';
    // Expired JWT: the session refreshes itself, so retrying works.
    if (code == 'PGRST301' || code == 'PGRST303') return true;
    // HTTP 5xx without a Postgres error body.
    final status = int.tryParse(code);
    if (status != null && status >= 500 && status < 600) return true;
    // Postgres connection / resource / serialization errors.
    return code.startsWith('08') ||
        code.startsWith('53') ||
        code.startsWith('57') ||
        code == '40001';
  }

  static String _postgrestMessage(PostgrestException error) {
    switch (error.code) {
      case '23505':
        if (error.message.contains('reports')) {
          return 'You have already reported this post.';
        }
        if (error.message.contains('username')) {
          return 'That username is already taken.';
        }
        return 'This already exists.';
      case '23503':
        return 'The item this belongs to no longer exists.';
      case '23502':
      case '23514':
      case '22001':
        return 'The content is empty or too long.';
      case '42501':
        // RLS rejections. Blocks are the usual cause for messages/follows.
        if (error.message.contains('direct_messages')) {
          return "You can't message this person.";
        }
        if (error.message.contains('follows')) {
          return "You can't follow this person.";
        }
        if (error.message.contains('comments')) {
          return "You can't comment on this post.";
        }
        return "You don't have permission to do that.";
      case 'PGRST116':
        return 'The item was not found.';
      case 'PGRST204':
      case 'PGRST205':
      case '42703':
      case '42P01':
        return 'The server database is out of date. '
            'Apply the latest Supabase migrations. (${error.message})';
      default:
        return error.message;
    }
  }

  @override
  String toString() => message;
}

/// Invalid user input, raised before anything is written.
class ValidationException extends AppException {
  const ValidationException(super.message);
}

/// Runs an online-only request with a timeout and turns any failure into an
/// [AppException] with a readable message.
Future<T> runOnline<T>(
  Future<T> Function() request, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  try {
    return await request().withNetworkTimeout(timeout);
  } catch (error) {
    throw AppException.from(error);
  }
}

extension TimeoutAsAppException<T> on Future<T> {
  /// Fails with a transient [AppException] when [duration] elapses.
  Future<T> withNetworkTimeout([
    Duration duration = const Duration(seconds: 15),
  ]) {
    return timeout(
      duration,
      onTimeout: () => throw AppException(
        'The server took too long to respond.',
        isTransient: true,
        cause: TimeoutException(null, duration),
      ),
    );
  }
}
