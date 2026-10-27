import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/app_exception.dart';
import '../models/models.dart';
import '../sync/outbox_operation.dart';

/// Everything the offline-first repository needs from the cloud.
abstract class RemoteDataSource {
  /// Latest posts in [scope] with their comments and reactions embedded.
  /// With [before], the page of posts older than that time.
  Future<List<Map<String, dynamic>>> fetchFeed(
    FeedScope scope, {
    int limit = 50,
    DateTime? before,
  });

  /// Sends one queued change to the cloud. Throws on failure.
  Future<void> apply(OutboxOperation operation);
}

class SupabaseRemoteDataSource implements RemoteDataSource {
  SupabaseRemoteDataSource(this._client);

  final SupabaseClient _client;
  bool _profileReady = false;

  static const feedColumns =
      'id, user_id, username, content, created_at, updated_at, '
      'group_id, media_url, media_type, tags, shared_post_id, '
      // The post being shared (null if deleted or hidden from the viewer).
      'shared:shared_post_id(id, user_id, username, content, '
      'media_url, media_type, created_at, author:profiles(profile_url)), '
      // Current profile picture of each author.
      'author:profiles(profile_url), '
      'comments(id, post_id, user_id, username, content, created_at, updated_at, '
      'parent_id, media_url, media_type, author:profiles(profile_url)), '
      'post_reactions(post_id, user_id, type)';

  @override
  Future<List<Map<String, dynamic>>> fetchFeed(
    FeedScope scope, {
    int limit = 50,
    DateTime? before,
  }) async {
    if (scope.kind == FeedKind.ids && scope.ids.isEmpty) return const [];
    var query = _client.from('posts').select(feedColumns);
    query = switch (scope.kind) {
      FeedKind.home => query.isFilter('group_id', null),
      FeedKind.group => query.eq('group_id', scope.value!),
      FeedKind.user =>
        query.eq('user_id', scope.value!).isFilter('group_id', null),
      FeedKind.tag => query.contains('tags', [scope.value!]),
      FeedKind.ids => query.inFilter('id', scope.ids),
    };
    if (before != null) {
      query = query.lt('created_at', before.toUtc().toIso8601String());
    }
    return await query
        .order('created_at', ascending: false)
        .limit(limit)
        .withNetworkTimeout();
  }

  @override
  Future<void> apply(OutboxOperation operation) async {
    final table = _client.from(operation.table);

    switch (operation.op) {
      case OutboxOp.upsert:
        await _ensureProfile();
        await table
            .upsert(operation.data, onConflict: operation.onConflict)
            .withNetworkTimeout();
      case OutboxOp.update:
        var query = table.update(operation.data);
        operation.match.forEach((column, value) {
          query = query.eq(column, value as Object);
        });
        final rows = await query.select('id').withNetworkTimeout();
        // RLS hides rows the user may not change, so nothing is updated and
        // no error is raised. Treat that as a permanent failure.
        if (rows.isEmpty) {
          throw const AppException(
            "This item was deleted or you can't edit it.",
          );
        }
      case OutboxOp.delete:
        var query = table.delete();
        operation.match.forEach((column, value) {
          query = query.eq(column, value as Object);
        });
        // Deleting a row that is already gone is fine.
        await query.withNetworkTimeout();
    }
  }

  /// posts.user_id references profiles.id, so the profile row must exist
  /// before the first post or comment is sent.
  Future<void> _ensureProfile() async {
    if (_profileReady) return;
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AppException('Your session has ended. Please log in again.');
    }
    final metadataName = user.userMetadata?['username']?.toString().trim();
    await _client
        .from('profiles')
        .upsert(
          {
            'id': user.id,
            'username': metadataName?.isNotEmpty == true
                ? metadataName
                : user.email?.split('@').first ?? 'user',
          },
          onConflict: 'id',
          ignoreDuplicates: true,
        )
        .withNetworkTimeout();
    _profileReady = true;
  }
}
