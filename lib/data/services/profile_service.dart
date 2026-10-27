import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/app_exception.dart';
import '../models/models.dart';

/// Profiles, follows and user search (online only).
class ProfileService {
  ProfileService(this._client, this.userId);

  static const profileColumns =
      'id, username, display_name, bio, profile_url, is_private, saved_public';
  static final _usernamePattern = RegExp(r'^[A-Za-z0-9_.]{3,30}$');

  final SupabaseClient _client;
  final String userId;

  Future<Profile> getProfile(String id) async {
    final row = await runOnline(
      () => _client
          .from('profiles')
          .select(profileColumns)
          .eq('id', id)
          .maybeSingle(),
    );
    if (row == null) throw const AppException('This user does not exist.');
    return Profile.fromMap(row);
  }

  Future<List<Profile>> getProfiles(Iterable<String> ids) async {
    final unique = ids.toSet().toList();
    if (unique.isEmpty) return const [];
    final rows = await runOnline(
      () => _client
          .from('profiles')
          .select(profileColumns)
          .inFilter('id', unique),
    );
    return rows.map(Profile.fromMap).toList();
  }

  /// Saves the signed-in user's profile and returns the stored version.
  Future<Profile> updateMyProfile({
    required String username,
    required String displayName,
    required String bio,
    required bool isPrivate,
    required bool savedPublic,
    String? avatarUrl,
  }) async {
    final name = username.trim();
    if (!_usernamePattern.hasMatch(name)) {
      throw const ValidationException(
        'Username must be 3–30 letters, numbers, "_" or ".".',
      );
    }
    if (displayName.trim().length > 50) {
      throw const ValidationException('Display name is too long (max 50).');
    }
    if (bio.trim().length > 300) {
      throw const ValidationException('Bio is too long (max 300 characters).');
    }

    final taken = await runOnline(
      () => _client
          .from('profiles')
          .select('id')
          .ilike('username', name)
          .neq('id', userId)
          .limit(1),
    );
    if (taken.isNotEmpty) {
      throw const ValidationException('That username is already taken.');
    }

    final row = await runOnline(
      () => _client
          .from('profiles')
          .upsert({
            'id': userId,
            'username': name,
            'display_name': displayName.trim().isEmpty
                ? null
                : displayName.trim(),
            'bio': bio.trim().isEmpty ? null : bio.trim(),
            'is_private': isPrivate,
            'saved_public': savedPublic,
            'profile_url': ?avatarUrl,
          })
          .select(profileColumns)
          .single(),
    );

    // Keep the auth metadata (used at sign-in) in step with the profile.
    try {
      await runOnline(
        () => _client.auth.updateUser(UserAttributes(data: {'username': name})),
      );
    } on AppException {
      // The profile row is the source of truth; metadata is only a fallback.
    }
    return Profile.fromMap(row);
  }

  Future<ProfileStats> getStats(String id) async {
    final results = await runOnline(
      () => Future.wait([
        _client
            .from('posts')
            .select('id')
            .eq('user_id', id)
            .isFilter('group_id', null)
            .count(CountOption.exact),
        _client
            .from('follows')
            .select('follower_id')
            .eq('following_id', id)
            .eq('status', 'accepted')
            .count(CountOption.exact),
        _client
            .from('follows')
            .select('following_id')
            .eq('follower_id', id)
            .eq('status', 'accepted')
            .count(CountOption.exact),
        if (id == userId)
          _client
              .from('follows')
              .select('follower_id')
              .eq('following_id', id)
              .eq('status', 'pending')
              .count(CountOption.exact),
      ]),
    );
    return ProfileStats(
      posts: results[0].count,
      followers: results[1].count,
      following: results[2].count,
      requests: results.length > 3 ? results[3].count : 0,
    );
  }

  /// How the signed-in user follows [targetId].
  Future<FollowStatus> followStatus(String targetId) async {
    if (targetId == userId) return FollowStatus.none;
    final row = await runOnline(
      () => _client
          .from('follows')
          .select('status')
          .eq('follower_id', userId)
          .eq('following_id', targetId)
          .maybeSingle(),
    );
    return switch (row?['status']) {
      'accepted' => FollowStatus.accepted,
      'pending' => FollowStatus.pending,
      _ => FollowStatus.none,
    };
  }

  /// Follows [targetId]. Private accounts get a request instead.
  Future<FollowStatus> follow(String targetId) async {
    if (targetId == userId) {
      throw const ValidationException("You can't follow yourself.");
    }
    final row = await runOnline(
      () => _client
          .from('follows')
          .upsert(
            {'follower_id': userId, 'following_id': targetId},
            onConflict: 'follower_id,following_id',
            ignoreDuplicates: true,
          )
          .select('status')
          .maybeSingle(),
    );
    if (row == null) return followStatus(targetId);
    return row['status'] == 'pending'
        ? FollowStatus.pending
        : FollowStatus.accepted;
  }

  /// Unfollows, or cancels a pending request.
  Future<void> unfollow(String targetId) => runOnline(
    () => _client
        .from('follows')
        .delete()
        .eq('follower_id', userId)
        .eq('following_id', targetId),
  );

  Future<void> acceptRequest(String followerId) async {
    final rows = await runOnline(
      () => _client
          .from('follows')
          .update({'status': 'accepted'})
          .eq('follower_id', followerId)
          .eq('following_id', userId)
          .select('follower_id'),
    );
    if (rows.isEmpty) {
      throw const AppException('This request was cancelled.');
    }
  }

  /// Rejects a request, or removes an existing follower.
  Future<void> removeFollower(String followerId) => runOnline(
    () => _client
        .from('follows')
        .delete()
        .eq('follower_id', followerId)
        .eq('following_id', userId),
  );

  Future<List<Profile>> followers(String id, {bool pending = false}) async {
    final rows = await runOnline(
      () => _client
          .from('follows')
          .select('follower_id')
          .eq('following_id', id)
          .eq('status', pending ? 'pending' : 'accepted')
          .order('created_at', ascending: false)
          .limit(200),
    );
    return _inOrder(rows.map((r) => r['follower_id'] as String).toList());
  }

  Future<List<Profile>> following(String id) async {
    final rows = await runOnline(
      () => _client
          .from('follows')
          .select('following_id')
          .eq('follower_id', id)
          .eq('status', 'accepted')
          .order('created_at', ascending: false)
          .limit(200),
    );
    return _inOrder(rows.map((r) => r['following_id'] as String).toList());
  }

  /// Users whose username or display name contains [query].
  Future<List<Profile>> searchUsers(String query) async {
    // Characters with meaning in PostgREST filters are dropped.
    final q = query.replaceAll(RegExp(r'[,()%*\\:"]'), ' ').trim();
    if (q.isEmpty) return const [];
    final rows = await runOnline(
      () => _client
          .from('profiles')
          .select(profileColumns)
          .or('username.ilike.%$q%,display_name.ilike.%$q%')
          .order('username')
          .limit(30),
    );
    return rows.map(Profile.fromMap).toList();
  }

  Future<List<Profile>> _inOrder(List<String> ids) async {
    final byId = {for (final p in await getProfiles(ids)) p.id: p};
    return [for (final id in ids) ?byId[id]];
  }
}
