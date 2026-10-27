import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/app_exception.dart';

/// Saved posts (online only). Who else may see them is the profile's
/// `saved_public` setting (see ProfileService.updateMyProfile).
class SavedService {
  SavedService(this._client, this.userId);

  final SupabaseClient _client;
  final String userId;

  /// Ids of the posts the signed-in user saved; drives the Save/Unsave menu.
  final mySaved = ValueNotifier<Set<String>>(const {});

  bool isSaved(String postId) => mySaved.value.contains(postId);

  Future<void> load() async {
    mySaved.value = (await savedPostIds(userId)).toSet();
  }

  /// Post ids saved by [ownerId], newest first. Empty when the owner keeps
  /// saved posts private (row-level security hides them).
  Future<List<String>> savedPostIds(String ownerId) async {
    final rows = await runOnline(
      () => _client
          .from('saved_posts')
          .select('post_id')
          .eq('user_id', ownerId)
          .order('created_at', ascending: false)
          .limit(200),
    );
    return [for (final r in rows) r['post_id'] as String];
  }

  Future<void> setSaved(String postId, bool save) async {
    final before = mySaved.value;
    mySaved.value = save ? {...before, postId} : ({...before}..remove(postId));
    try {
      if (save) {
        await runOnline(
          () => _client
              .from('saved_posts')
              .upsert(
                {'user_id': userId, 'post_id': postId},
                onConflict: 'user_id,post_id',
                ignoreDuplicates: true,
              ),
        );
      } else {
        await runOnline(
          () => _client
              .from('saved_posts')
              .delete()
              .eq('user_id', userId)
              .eq('post_id', postId),
        );
      }
    } catch (error) {
      mySaved.value = before;
      rethrow;
    }
  }

  void dispose() => mySaved.dispose();
}
