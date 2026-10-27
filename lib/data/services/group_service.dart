import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/app_exception.dart';
import '../models/models.dart';
import 'profile_service.dart';

/// Groups and pages: create / join / edit / leave / delete (online only).
/// Their posts go through the offline-first SocialRepository.
class GroupService {
  GroupService(this._client, this.userId);

  final SupabaseClient _client;
  final String userId;

  String get _columns =>
      'id, name, description, kind, created_by, created_at, '
      'avatar_url, cover_url, '
      'group_members(count), '
      'me:group_members(user_id, role, notify)';

  Group _parse(Map<String, dynamic> row) {
    final members = [
      ...(row['group_members'] as List? ?? const []),
      ...(row['me'] as List? ?? const []).where((m) => m['user_id'] == userId),
    ];
    return Group.fromMap({...row, 'group_members': members}, me: userId);
  }

  /// All groups/pages, newest first, optionally filtered by name.
  Future<List<Group>> listGroups({String query = ''}) async {
    final q = query.replaceAll(RegExp(r'[,()%*\\:"]'), ' ').trim();
    final rows = await runOnline(() {
      var request = _client
          .from('groups')
          .select(_columns)
          .eq('me.user_id', userId);
      if (q.isNotEmpty) request = request.ilike('name', '%$q%');
      return request.order('created_at', ascending: false).limit(100);
    });
    return rows.map(_parse).toList();
  }

  Future<Group> getGroup(String id) async {
    final row = await runOnline(
      () => _client
          .from('groups')
          .select(_columns)
          .eq('id', id)
          .eq('me.user_id', userId)
          .maybeSingle(),
    );
    if (row == null) {
      throw const AppException('This group was deleted.');
    }
    return _parse(row);
  }

  Future<Group> createGroup({
    required String name,
    required String description,
    required GroupKind kind,
  }) async {
    _validate(name, description);
    final row = await runOnline(
      () => _client
          .from('groups')
          .insert({
            'name': name.trim(),
            'description': description.trim().isEmpty
                ? null
                : description.trim(),
            'kind': kind.name,
            'created_by': userId,
          })
          .select('id')
          .single(),
    );
    // The owner membership is added by a database trigger.
    return getGroup(row['id'] as String);
  }

  /// Saves name/description, and the picture/banner when given (already
  /// uploaded URLs).
  Future<Group> updateGroup(
    String id, {
    required String name,
    required String description,
    String? avatarUrl,
    String? coverUrl,
  }) async {
    _validate(name, description);
    final rows = await runOnline(
      () => _client
          .from('groups')
          .update({
            'name': name.trim(),
            'description': description.trim().isEmpty
                ? null
                : description.trim(),
            'avatar_url': ?avatarUrl,
            'cover_url': ?coverUrl,
          })
          .eq('id', id)
          .select('id'),
    );
    if (rows.isEmpty) {
      throw const AppException(
        'Only the owner or an admin can edit this group.',
      );
    }
    return getGroup(id);
  }

  Future<void> deleteGroup(String id) async {
    final rows = await runOnline(
      () => _client.from('groups').delete().eq('id', id).select('id'),
    );
    if (rows.isEmpty) {
      throw const AppException('Only the owner can delete this group.');
    }
  }

  Future<void> join(String groupId) => runOnline(
    () => _client
        .from('group_members')
        .upsert(
          {'group_id': groupId, 'user_id': userId, 'role': 'member'},
          onConflict: 'group_id,user_id',
          ignoreDuplicates: true,
        ),
  );

  /// Turns new-post notifications from [groupId] on or off for me.
  Future<void> setNotifications(String groupId, bool enabled) => runOnline(
    () => _client.rpc(
      'set_group_notifications',
      params: {'gid': groupId, 'enabled': enabled},
    ),
  );

  Future<void> leave(Group group) async {
    if (group.myRole == GroupRole.owner) {
      throw const ValidationException(
        'Owners cannot leave. Delete the group instead.',
      );
    }
    await runOnline(
      () => _client
          .from('group_members')
          .delete()
          .eq('group_id', group.id)
          .eq('user_id', userId),
    );
  }

  Future<List<GroupMember>> members(String groupId) async {
    final rows = await runOnline(
      () => _client
          .from('group_members')
          .select('user_id, role')
          .eq('group_id', groupId)
          .order('joined_at')
          .limit(500),
    );
    final profiles = {
      for (final p in await ProfileService(
        _client,
        userId,
      ).getProfiles(rows.map((r) => r['user_id'] as String)))
        p.id: p,
    };
    return [
      for (final row in rows)
        if (profiles[row['user_id']] case final profile?)
          GroupMember(
            profile: profile,
            role: GroupRole.values.asNameMap()[row['role']] ?? GroupRole.member,
          ),
    ];
  }

  Future<void> removeMember(String groupId, String memberId) async {
    final rows = await runOnline(
      () => _client
          .from('group_members')
          .delete()
          .eq('group_id', groupId)
          .eq('user_id', memberId)
          .select('user_id'),
    );
    if (rows.isEmpty) {
      throw const AppException("You can't remove this member.");
    }
  }

  /// Owner only: makes a member staff (admin) or back to a regular member.
  Future<void> setRole(String groupId, String memberId, GroupRole role) async {
    if (role == GroupRole.owner) {
      throw const ValidationException('A group has exactly one owner.');
    }
    final rows = await runOnline(
      () => _client
          .from('group_members')
          .update({'role': role.name})
          .eq('group_id', groupId)
          .eq('user_id', memberId)
          .select('user_id'),
    );
    if (rows.isEmpty) {
      throw const AppException('Only the owner can change roles.');
    }
  }

  /// Pending reports on posts in [groupId] (owner/staff only).
  Future<List<GroupReport>> reports(String groupId) async {
    final rows = await runOnline(
      () => _client
          .from('reports')
          .select(
            'id, post_id, reason, details, status, created_at, reported_by, '
            'post:posts!inner(username, content, media_url, media_type, group_id)',
          )
          .eq('post.group_id', groupId)
          .eq('status', 'pending')
          .order('created_at', ascending: false)
          .limit(200),
    );
    final reporters = {
      for (final p in await ProfileService(
        _client,
        userId,
      ).getProfiles(rows.map((r) => r['reported_by'] as String)))
        p.id: p,
    };
    return [
      for (final row in rows)
        GroupReport.fromMap(row, reporters[row['reported_by']]),
    ];
  }

  Future<int> pendingReportCount(String groupId) async {
    final result = await runOnline(
      () => _client
          .from('reports')
          .select('id, post:posts!inner(group_id)')
          .eq('post.group_id', groupId)
          .eq('status', 'pending')
          .count(CountOption.exact),
    );
    return result.count;
  }

  /// Keeps the post and closes the report.
  Future<void> dismissReport(GroupReport report) async {
    final rows = await runOnline(
      () => _client
          .from('reports')
          .update({
            'status': 'dismissed',
            'reviewed_by': userId,
            'reviewed_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', report.id)
          .select('id'),
    );
    if (rows.isEmpty) {
      throw const AppException('Only group staff can review reports.');
    }
  }

  /// Deletes the reported post (its reports are deleted with it).
  Future<void> removeReportedPost(GroupReport report) async {
    final rows = await runOnline(
      () => _client.from('posts').delete().eq('id', report.postId).select('id'),
    );
    if (rows.isEmpty) {
      throw const AppException(
        'The post was already deleted, or you are not group staff.',
      );
    }
  }

  void _validate(String name, String description) {
    if (name.trim().isEmpty) {
      throw const ValidationException('Give the group a name.');
    }
    if (name.trim().length > 80) {
      throw const ValidationException('Name is too long (max 80).');
    }
    if (description.trim().length > 500) {
      throw const ValidationException('Description is too long (max 500).');
    }
  }
}
