import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/app_exception.dart';
import '../models/models.dart';
import 'profile_service.dart';

/// Blocking people (online only). The database hides posts, comments,
/// messages and follows between blocked people in both directions.
class BlockService {
  BlockService(this._client, this.userId, this._profiles);

  final SupabaseClient _client;
  final String userId;
  final ProfileService _profiles;

  /// Ids of people the signed-in user blocked.
  final blocked = ValueNotifier<Set<String>>(const {});

  bool isBlocked(String otherId) => blocked.value.contains(otherId);

  Future<void> load() async {
    final rows = await runOnline(
      () =>
          _client.from('blocks').select('blocked_id').eq('blocker_id', userId),
    );
    blocked.value = {for (final r in rows) r['blocked_id'] as String};
  }

  Future<void> block(String otherId) async {
    if (otherId == userId) {
      throw const ValidationException("You can't block yourself.");
    }
    await runOnline(
      () => _client
          .from('blocks')
          .upsert(
            {'blocker_id': userId, 'blocked_id': otherId},
            onConflict: 'blocker_id,blocked_id',
            ignoreDuplicates: true,
          ),
    );
    blocked.value = {...blocked.value, otherId};
  }

  Future<void> unblock(String otherId) async {
    await runOnline(
      () => _client
          .from('blocks')
          .delete()
          .eq('blocker_id', userId)
          .eq('blocked_id', otherId),
    );
    blocked.value = {...blocked.value}..remove(otherId);
  }

  Future<List<Profile>> blockedProfiles() async {
    await load();
    return _profiles.getProfiles(blocked.value);
  }

  void dispose() => blocked.dispose();
}
