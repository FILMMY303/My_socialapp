import 'package:appsocial/core/errors/app_exception.dart';
import 'package:appsocial/core/utils/time_ago.dart';
import 'package:appsocial/data/models/models.dart';
import 'package:appsocial/data/services/media_service.dart';
import 'package:appsocial/data/sync/outbox_operation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Post post(String id) => Post.fromMap({
  'id': id,
  'user_id': 'u',
  'username': 'u',
  'content': '',
  'created_at': '2026-10-01T00:00:00Z',
});

void main() {
  test('1. extractTags lower-cases, strips # and removes duplicates', () {
    expect(extractTags('Hi #Flutter and #flutter, also #Dart!'), [
      'flutter',
      'dart',
    ]);
    expect(extractTags('no tags here'), isEmpty);
  });

  test('2. timeAgo picks the right unit for the elapsed time', () {
    final now = DateTime.now();
    expect(timeAgo(now.subtract(const Duration(seconds: 10))), 'Just now');
    expect(timeAgo(now.subtract(const Duration(minutes: 5))), '5 min');
    expect(timeAgo(now.subtract(const Duration(hours: 3))), '3 hr');
    expect(timeAgo(now.subtract(const Duration(days: 2))), '2 d');
    final old = DateTime(2025, 1, 15);
    expect(timeAgo(old), '15/1/2025');
  });

  test('3. initialOf returns an upper-case first letter or ?', () {
    expect(initialOf('  alice '), 'A');
    expect(initialOf('   '), '?');
    expect(initialOf(''), '?');
  });

  test('4. FeedScope.tag normalises the tag and matches tagged posts', () {
    final scope = FeedScope.tag('#Flutter');
    expect(scope.value, 'flutter');
    expect(scope, FeedScope.tag('flutter'));
    expect(
      scope.matches({
        'tags': ['flutter'],
      }),
      isTrue,
    );
    expect(scope.matches({'tags': null}), isFalse);
  });

  test('5. FeedScope home/user/ids match the right posts', () {
    const home = FeedScope.home();
    const user = FeedScope.user('u1');
    final ids = FeedScope.ids(['a', 'b']);

    expect(home.matches({'group_id': null}), isTrue);
    expect(home.matches({'group_id': 'g1'}), isFalse);
    expect(user.matches({'user_id': 'u1', 'group_id': null}), isTrue);
    expect(user.matches({'user_id': 'u1', 'group_id': 'g1'}), isFalse);
    expect(ids.ids, ['a', 'b']);
    expect(ids.matches({'id': 'b'}), isTrue);
    expect(FeedScope.ids([]).ids, isEmpty);
  });

  test('6. FeedPost counts reactions and sorts top emoji (incl. dislike)', () {
    final feedPost = FeedPost(
      post: post('p1'),
      isMine: false,
      reactions: {
        ReactionType.like: 2,
        ReactionType.love: 5,
        ReactionType.dislike: 9,
        ReactionType.sad: 0,
      },
    );
    expect(feedPost.likes, 2);
    expect(feedPost.dislikes, 9);
    expect(feedPost.topEmoji, [
      ReactionType.dislike,
      ReactionType.love,
      ReactionType.like,
    ]);
    expect(feedPost.emojiTotal, 16);
    expect(ReactionType.emojiReactions.last, ReactionType.dislike);
  });

  test('7. Group.fromMap reads member count and my role', () {
    final group = Group.fromMap({
      'id': 'g1',
      'name': 'Flutter TH',
      'kind': 'group',
      'created_by': 'owner',
      'group_members': [
        {'count': 12},
        {'user_id': 'me', 'role': 'admin'},
      ],
    }, me: 'me');
    expect(group.memberCount, 12);
    expect(group.myRole, GroupRole.admin);
    expect(group.isAdmin, isTrue);
    expect(group.isOwner, isFalse);
    expect(group.canPost, isTrue);
  });

  test('8. only admins can post on a page; non-members cannot post', () {
    Group make(String kind, String? role) => Group.fromMap({
      'id': 'g',
      'name': 'n',
      'kind': kind,
      'created_by': 'x',
      'group_members': [
        if (role != null) {'user_id': 'me', 'role': role},
      ],
    }, me: 'me');

    expect(make('page', 'member').canPost, isFalse);
    expect(make('page', 'owner').canPost, isTrue);
    expect(make('group', 'member').canPost, isTrue);
    expect(make('group', null).canPost, isFalse);
    expect(make('group', null).isMember, isFalse);
  });

  test('9. OutboxOperation survives a toMap/fromMap round trip', () {
    const original = OutboxOperation(
      table: 'post_reactions',
      op: OutboxOp.upsert,
      entityKey: 'reactions:p1',
      data: {'post_id': 'p1', 'type': 'love'},
      onConflict: 'post_id,user_id',
      attempts: 3,
      lastError: 'offline',
    );
    final copy = OutboxOperation.fromMap(7, original.toMap());

    expect(copy.key, 7);
    expect(copy.table, original.table);
    expect(copy.op, OutboxOp.upsert);
    expect(copy.entityKey, original.entityKey);
    expect(copy.data, original.data);
    expect(copy.match, isEmpty);
    expect(copy.onConflict, original.onConflict);
    expect(copy.attempts, 3);
    expect(copy.lastError, 'offline');
  });

  test('10. AppException.from maps Postgres errors to friendly messages', () {
    final duplicate = AppException.from(
      const PostgrestException(
        message: 'duplicate key value violates "profiles_username_key"',
        code: '23505',
      ),
    );
    expect(duplicate.message, 'That username is already taken.');
    expect(duplicate.isTransient, isFalse);

    final serverDown = AppException.from(
      const PostgrestException(message: 'bad gateway', code: '502'),
    );
    expect(serverDown.isTransient, isTrue);

    final unknown = AppException.from(Exception('socket closed'));
    expect(unknown.isTransient, isTrue);

    const validation = ValidationException('Empty post');
    expect(AppException.from(validation), same(validation));
  });

  test('11. videos up to 2 minutes are accepted, longer ones rejected', () {
    expect(
      () => MediaService.checkVideoDuration(const Duration(minutes: 2)),
      returnsNormally,
    );
    expect(
      () => MediaService.checkVideoDuration(const Duration(seconds: 15)),
      returnsNormally,
    );
    expect(
      () => MediaService.checkVideoDuration(
        const Duration(minutes: 2, milliseconds: 500),
      ),
      throwsA(isA<ValidationException>()),
    );
    expect(
      () => MediaService.checkVideoDuration(null),
      throwsA(isA<ValidationException>()),
    );
  });

  test('12. long video error shows the length as m:ss', () {
    expect(MediaService.formatDuration(const Duration(seconds: 185)), '3:05');
    expect(
      () => MediaService.checkVideoDuration(const Duration(seconds: 185)),
      throwsA(
        isA<ValidationException>().having(
          (e) => e.message,
          'message',
          contains('This one is 3:05'),
        ),
      ),
    );
  });

  test('13. group/page notifications: pages default on, groups off', () {
    Group make(String kind, {String? role = 'member', bool? notify}) =>
        Group.fromMap({
          'id': 'g',
          'name': 'n',
          'kind': kind,
          'created_by': 'x',
          'group_members': [
            if (role != null) {'user_id': 'me', 'role': role, 'notify': notify},
          ],
        }, me: 'me');

    expect(make('page').notificationsOn, isTrue);
    expect(make('group').notificationsOn, isFalse);
    expect(make('page', notify: false).notificationsOn, isFalse);
    expect(make('group', notify: true).notificationsOn, isTrue);
    expect(make('page', role: null).notificationsOn, isFalse);
    expect(ActivityType.parse('group_post'), ActivityType.groupPost);
  });
}
