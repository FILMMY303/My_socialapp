import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/app_exception.dart';
import '../models/models.dart';

/// Reporting inappropriate posts (online only).
class ReportService {
  ReportService(this._client, this.userId);

  static const maxDetailsLength = 500;

  final SupabaseClient _client;
  final String userId;

  Future<void> reportPost(
    String postId,
    ReportReason reason, {
    String details = '',
  }) async {
    if (details.trim().length > maxDetailsLength) {
      throw const ValidationException('Details are too long (max 500).');
    }
    if (reason == ReportReason.other && details.trim().isEmpty) {
      throw const ValidationException('Tell us what is wrong with this post.');
    }
    await runOnline(
      () => _client.from('reports').insert({
        'post_id': postId,
        'reported_by': userId,
        'reason': reason.value,
        'details': details.trim().isEmpty ? null : details.trim(),
      }),
    );
  }
}
