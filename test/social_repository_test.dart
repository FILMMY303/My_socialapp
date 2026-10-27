import 'package:appsocial/core/errors/app_exception.dart';
import 'package:appsocial/data/local/local_database.dart';
import 'package:appsocial/data/models/models.dart';
import 'package:appsocial/data/remote/remote_data_source.dart';
import 'package:appsocial/data/repositories/social_repository.dart';
import 'package:appsocial/data/sync/outbox_operation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeRemote implements RemoteDataSource {
  final applied = <OutboxOperation>[];
  List<Map<String, dynamic>> feed = [];

  /// When set, every call throws this.
  Object? failure;

  /// When set, only sending changes fails (fetching still works).
  Object? pushFailure;

  @override
  Future<void> apply(OutboxOperation operation) async {
    if (failure != null) throw failure!;
    if (pushFailure != null) throw pushFailure!;
    applied.add(operation);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchFeed(
    FeedScope scope, {
    int limit = 50,
    DateTime? before,
  }) async {
    if (failure != null) throw failure!;
    final rows =
        [
          for (final row in feed)
            if (scope.matches(row) &&
                (before == null ||
                    DateTime.parse(row['created_at'] as String)
                        .isBefore(before)))
              row,
        ]..sort(
          (a, b) =>
              (b['created_at'] as String).compareTo(a['created_at'] as String),
        );
    return rows.take(limit).toList();
  }
}

const me = 'user-1';

void main() {
  late FakeRemote remote;
  late SocialRepository repo;

  setUp(() async {
    remote = FakeRemote();
    repo = SocialRepository(
      local: await LocalDatabase.openWith(newDatabaseFactoryMemory(), 't.db'),
      remote: remote,
      userId: me,
      username: 'me',
      retryInterval: Duration.zero,
    );
  });

  tearDown(() => repo.dispose());

  Future<List<FeedPost>> feed() => repo.watchFeed().first;

  test('create post is saved locally and pushed to the cloud', () async {
    await repo.createPost('  hello  ');
    await repo.sync();

    final posts = await feed();
    expect(posts.single.post.content, 'hello');
    expect(posts.single.post.syncStatus, SyncStatus.synced);
    expect(remote.applied.single.op, OutboxOp.upsert);
    expect(remote.applied.single.data['content'], 'hello');
    expect(repo.syncState.pendingChanges, 0);
  });

  test('offline changes stay queued and sync later in order', () async {
    remote.failure = Exception('SocketException: no network');
    await repo.createPost('first');
    final id = (await feed()).single.post.id;
    await repo.updatePost(id, 'edited');
    await repo.sync();

    expect(repo.syncState.isOffline, isTrue);
    expect(repo.syncState.pendingChanges, 2);
    expect((await feed()).single.post.content, 'edited');
    expect((await feed()).single.post.syncStatus, SyncStatus.pending);

    remote.failure = null;
    await repo.sync();

    expect(remote.applied.map((op) => op.op), [
      OutboxOp.upsert,
      OutboxOp.update,
    ]);
    expect(repo.syncState.pendingChanges, 0);
    expect(repo.syncState.isOffline, isFalse);
    expect((await feed()).single.post.syncStatus, SyncStatus.synced);
  });

  test('delete removes the post once the cloud confirms', () async {
    await repo.createPost('bye');
    await repo.sync();
    final id = (await feed()).single.post.id;

    await repo.deletePost(id);
    expect(await feed(), isEmpty);
    await repo.sync();

    expect(remote.applied.last.op, OutboxOp.delete);
    expect(await repo.local.posts.record(id).get(repo.local.db), isNull);
  });

  test('a rejected change is dropped and reported', () async {
    final errors = <String>[];
    repo.errors.listen(errors.add);

    remote.failure = const PostgrestException(
      message: 'new row violates row-level security policy',
      code: '42501',
    );
    await repo.createPost('not allowed');
    await repo.sync();
    await Future<void>.delayed(Duration.zero);

    expect(repo.syncState.pendingChanges, 0);
    expect(errors.single, contains("don't have permission"));
  });

  test('refresh keeps local edits that are not synced yet', () async {
    remote.feed = [
      {
        'id': 'p1',
        'user_id': me,
        'username': 'me',
        'content': 'cloud text',
        'created_at': '2026-10-01T00:00:00Z',
        'updated_at': null,
        'comments': [
          {
            'id': 'c1',
            'post_id': 'p1',
            'user_id': 'user-2',
            'username': 'friend',
            'content': 'nice',
            'created_at': '2026-10-01T01:00:00Z',
            'updated_at': null,
          },
        ],
        'post_reactions': [
          {'post_id': 'p1', 'user_id': 'user-2', 'type': 'like'},
        ],
      },
    ];
    await repo.refresh();

    var item = (await feed()).single;
    expect(item.comments, 1);
    expect(item.likes, 1);

    remote.pushFailure = Exception('offline');
    await repo.updatePost('p1', 'local text');
    await repo.setReaction('p1', ReactionType.dislike);
    await repo.sync();
    expect(repo.syncState.pendingChanges, 2);

    // A pull while the changes are still queued must not overwrite them.
    remote.feed.first['content'] = 'cloud text';
    try {
      await repo.refresh();
    } on AppException {
      // refresh() fails only if fetching fails; pushing is retried later.
    }
    item = (await feed()).single;
    expect(item.post.content, 'local text');
    expect(item.dislikes, 1);
    expect(item.myReaction, ReactionType.dislike);

    remote.pushFailure = null;
    remote.feed.first['content'] = 'local text';
    remote.feed.first['post_reactions'] = [
      {'post_id': 'p1', 'user_id': 'user-2', 'type': 'like'},
      {'post_id': 'p1', 'user_id': me, 'type': 'dislike'},
    ];
    await repo.refresh();
    expect(remote.applied.map((op) => op.table), ['posts', 'post_reactions']);
    item = (await feed()).single;
    expect(item.post.content, 'local text');
    expect(item.post.syncStatus, SyncStatus.synced);
    expect(item.likes, 1);
    expect(item.dislikes, 1);
  });

  test('comments: add, edit, delete', () async {
    await repo.createPost('post');
    final postId = (await feed()).single.post.id;

    await repo.addComment(postId, 'first');
    var comments = await repo.watchComments(postId).first;
    expect(comments.single.content, 'first');

    await repo.updateComment(comments.single.id, 'changed');
    comments = await repo.watchComments(postId).first;
    expect(comments.single.content, 'changed');
    expect(comments.single.isEdited, isTrue);

    await repo.deleteComment(comments.single.id);
    expect(await repo.watchComments(postId).first, isEmpty);
    expect((await feed()).single.comments, 0);
  });

  test('validation rejects empty and too long content', () async {
    expect(repo.createPost('   '), throwsA(isA<ValidationException>()));
    expect(
      repo.createPost('x' * (SocialRepository.maxPostLength + 1)),
      throwsA(isA<ValidationException>()),
    );
  });

  test("cannot edit someone else's post", () async {
    remote.feed = [
      {
        'id': 'p2',
        'user_id': 'user-2',
        'username': 'friend',
        'content': 'theirs',
        'created_at': '2026-10-01T00:00:00Z',
      },
    ];
    await repo.refresh();
    expect(repo.updatePost('p2', 'hacked'), throwsA(isA<AppException>()));
    expect(repo.deletePost('p2'), throwsA(isA<AppException>()));
  });

  Map<String, dynamic> cloudPost(String id, {String? groupId, String? text}) =>
      {
        'id': id,
        'user_id': 'user-2',
        'username': 'friend',
        'content': text ?? 'post $id',
        'created_at': '2026-10-01T00:00:00Z',
        'group_id': groupId,
        'tags': extractTags(text ?? ''),
      };

  test('scoped feeds: refreshing one scope keeps the others', () async {
    remote.feed = [cloudPost('home1'), cloudPost('g1', groupId: 'group-a')];
    await repo.refresh();
    await repo.refresh(const FeedScope.group('group-a'));

    expect((await feed()).map((p) => p.post.id), ['home1']);
    expect(
      (await repo.watchFeed(const FeedScope.group('group-a')).first).map(
        (p) => p.post.id,
      ),
      ['g1'],
    );

    // home1 deleted in the cloud: the home refresh drops it, g1 stays.
    remote.feed = [cloudPost('g1', groupId: 'group-a')];
    await repo.refresh();
    expect(await feed(), isEmpty);
    expect(
      await repo.watchFeed(const FeedScope.group('group-a')).first,
      hasLength(1),
    );
  });

  test('group posts and hashtags', () async {
    await repo.createPost('hello #Flutter #flutter #ไทย', groupId: 'group-a');
    expect(await feed(), isEmpty);

    final groupFeed = await repo
        .watchFeed(const FeedScope.group('group-a'))
        .first;
    expect(groupFeed.single.post.tags, unorderedEquals(['flutter', 'ไทย']));
    expect(await repo.watchFeed(FeedScope.tag('#FLUTTER')).first, hasLength(1));
    await repo.sync();
    expect(remote.applied.single.data['group_id'], 'group-a');
  });

  test('media posts may have no text', () async {
    await repo.createPost(
      '',
      media: const MediaRef(url: 'https://x/y.jpg', type: MediaType.image),
    );
    final post = (await feed()).single.post;
    expect(post.media?.type, MediaType.image);
    expect(repo.updatePost(post.id, '  '), completes);
  });

  test('emoji reactions are counted per type', () async {
    remote.feed = [
      {
        ...cloudPost('p1'),
        'post_reactions': [
          {'post_id': 'p1', 'user_id': 'a', 'type': 'love'},
          {'post_id': 'p1', 'user_id': 'b', 'type': 'love'},
          {'post_id': 'p1', 'user_id': 'c', 'type': 'haha'},
          {'post_id': 'p1', 'user_id': 'd', 'type': 'dislike'},
        ],
      },
    ];
    await repo.refresh();
    await repo.setReaction('p1', ReactionType.wow);

    final item = (await feed()).single;
    expect(item.reactions[ReactionType.love], 2);
    expect(item.dislikes, 1);
    expect(item.emojiTotal, 5);
    expect(item.topEmoji.first, ReactionType.love);
    expect(item.myReaction, ReactionType.wow);
  });

  test('author pictures come from the profile and update at once', () async {
    remote.feed = [
      {
        ...cloudPost('p1'),
        'user_id': me,
        'author': {'profile_url': 'https://x/old.png'},
        'comments': [
          {
            'id': 'c1',
            'post_id': 'p1',
            'user_id': me,
            'username': 'me',
            'content': 'hi',
            'created_at': '2026-10-01T01:00:00Z',
            'author': {'profile_url': 'https://x/old.png'},
          },
        ],
      },
    ];
    await repo.refresh();
    expect((await feed()).single.post.avatarUrl, 'https://x/old.png');

    await repo.setMyAvatar('https://x/new.png');
    expect((await feed()).single.post.avatarUrl, 'https://x/new.png');
    final comment = (await repo.watchComments('p1').first).single;
    expect(comment.avatarUrl, 'https://x/new.png');

    await repo.createPost('fresh');
    expect(
      (await feed())
          .firstWhere((p) => p.post.content == 'fresh')
          .post
          .avatarUrl,
      'https://x/new.png',
    );
  });

  test(
    'replies and media comments; deleting a comment hides its replies',
    () async {
      await repo.createPost('post');
      final postId = (await feed()).single.post.id;

      await repo.addComment(
        postId,
        '',
        media: const MediaRef(url: 'https://x/c.jpg', type: MediaType.image),
      );
      final parent = (await repo.watchComments(postId).first).single;
      expect(parent.media?.type, MediaType.image);

      await repo.addComment(postId, 'a reply', parentId: parent.id);
      var comments = await repo.watchComments(postId).first;
      expect(comments.last.parentId, parent.id);
      expect((await feed()).single.comments, 2);

      await repo.sync();
      expect(remote.applied.last.data['parent_id'], parent.id);

      await repo.deleteComment(parent.id);
      comments = await repo.watchComments(postId).first;
      expect(comments, isEmpty);
      await repo.sync();
      expect(await repo.local.comments.count(repo.local.db), 0);

      expect(
        repo.addComment(postId, 'orphan', parentId: parent.id),
        throwsA(isA<AppException>()),
      );
    },
  );

  test('ids scope shows exactly the requested posts', () async {
    remote.feed = [cloudPost('a'), cloudPost('b'), cloudPost('c')];
    final scope = FeedScope.ids(['a', 'c']);
    await repo.refresh(scope);
    final posts = await repo.watchFeed(scope).first;
    expect(posts.map((p) => p.post.id).toSet(), {'a', 'c'});
  });

  test('notification text', () {
    ActivityNotification? parse(String type, {Map<String, dynamic>? post}) =>
        ActivityNotification.fromMap({
          'id': 'n1',
          'type': type,
          'created_at': '2026-10-01T00:00:00Z',
          'actor': {'id': 'u2', 'username': 'ann'},
          'post': post,
          'group': {'name': 'Cats'},
        });

    expect(parse('follow')!.text, 'ann started following you.');
    expect(parse('follow_request')!.text, 'ann requested to follow you.');
    expect(
      parse('friend_post', post: {'content': 'hello'})!.text,
      'ann posted: "hello"',
    );
    expect(
      parse('page_post', post: {'content': '', 'media_type': 'video'})!.text,
      'Cats posted: "a video"',
    );
    expect(parse('something_new'), isNull);

    // Page posts show the page; everything else shows the person.
    final pagePost = parse('page_post')!;
    expect(pagePost.isFromPage, isTrue);
    expect(pagePost.displayName, 'Cats');
    expect(parse('follow')!.displayName, 'ann');
  });

  test(
    'sharing a post (and re-sharing a share points at the original)',
    () async {
      remote.feed = [cloudPost('orig', text: 'original text')];
      await repo.refresh();
      final original = (await feed()).single.post;

      await repo.createPost('', share: original);
      final share = (await feed()).firstWhere((p) => p.post.isShare).post;
      expect(share.sharedPostId, 'orig');
      expect(share.shared?.content, 'original text'); // snapshot, works offline

      await repo.createPost('again', share: share);
      final reshare = (await feed()).firstWhere(
        (p) => p.post.content == 'again',
      );
      expect(reshare.post.sharedPostId, 'orig');

      await repo.sync();
      expect(remote.applied.first.data['shared_post_id'], 'orig');
    },
  );

  String at(int minutes) => DateTime.utc(
    2026,
    10,
    1,
  ).add(Duration(minutes: minutes)).toIso8601String();

  test('load more fetches older pages and refresh keeps them', () async {
    final total = SocialRepository.pageSize + 20;
    remote.feed = [
      for (var i = 0; i < total; i++)
        {...cloudPost('p$i'), 'created_at': at(i)},
    ];
    await repo.refresh();
    expect(await feed(), hasLength(SocialRepository.pageSize));

    final more = await repo.loadMore(const FeedScope.home());
    expect(more, isFalse); // the second page was short: nothing older
    expect(await feed(), hasLength(total));

    // A refresh only covers the newest page; older posts stay.
    await repo.refresh();
    expect(await feed(), hasLength(total));
  });

  test('blocking removes that person\'s cached posts and comments', () async {
    remote.feed = [
      {
        ...cloudPost('p1'),
        'comments': [
          {
            'id': 'c1',
            'post_id': 'p1',
            'user_id': 'user-3',
            'username': 'carol',
            'content': 'hi',
            'created_at': '2026-10-01T01:00:00Z',
          },
        ],
      },
      {...cloudPost('p2'), 'user_id': 'user-3'},
    ];
    await repo.refresh();
    expect(await feed(), hasLength(2));

    await repo.removeUserContent('user-3');
    expect((await feed()).map((p) => p.post.id), ['p1']);
    expect(await repo.watchComments('p1').first, isEmpty);
  });

  test('comment, reply, reaction and share notifications', () {
    ActivityNotification n(String type, {String? reaction}) =>
        ActivityNotification.fromMap({
          'id': 'n',
          'type': type,
          'post_id': 'p1',
          'reaction': reaction,
          'created_at': '2026-10-01T00:00:00Z',
          'actor': {'id': 'u2', 'username': 'ann'},
        })!;

    expect(n('comment').text, 'ann commented on your post.');
    expect(n('reply').text, 'ann replied to your comment.');
    expect(
      n('reaction', reaction: 'love').text,
      'ann reacted ❤️ to your post.',
    );
    expect(n('share').text, 'ann shared your post.');
    expect(n('share').isAboutPost, isTrue);
  });

  test('hidden (reported) posts disappear from every feed', () async {
    remote.feed = [cloudPost('p1'), cloudPost('p2')];
    await repo.refresh();
    await repo.hidePost('p1');
    expect((await feed()).map((p) => p.post.id), ['p2']);
    await repo.refresh();
    expect((await feed()).map((p) => p.post.id), ['p2']);
  });
}
