import 'dart:async';

import 'package:sembast/sembast.dart';
import 'package:uuid/uuid.dart';

import '../../core/errors/app_exception.dart';
import '../local/local_database.dart';
import '../models/models.dart';
import '../remote/remote_data_source.dart';
import '../sync/outbox_operation.dart';

/// Single entry point for posts, comments and reactions.
///
/// Data flow (offline-first):
///   UI -> repository -> local database + outbox  (instant, works offline)
///                    -> outbox is sent to the cloud in order (sync)
///   cloud -> refresh() -> local database -> UI streams
///
/// The UI only reads from the local database, so it updates immediately and
/// keeps working without a connection.
class SocialRepository {
  SocialRepository({
    required this.local,
    required this.remote,
    required this.userId,
    required this.username,
    Duration retryInterval = const Duration(seconds: 20),
  }) {
    if (retryInterval > Duration.zero) {
      _timer = Timer.periodic(retryInterval, (_) => _onTick());
    }
  }

  static const maxPostLength = 2000;
  static const maxCommentLength = 1000;

  final LocalDatabase local;
  final RemoteDataSource remote;
  final String userId;

  /// Name stamped on new posts and comments; updated when the profile changes.
  String username;

  /// Profile picture shown on the user's new posts until the next refresh.
  String? avatarUrl;

  final _uuid = const Uuid();
  final _changes = StreamController<void>.broadcast();
  final _errors = StreamController<String>.broadcast();
  final _syncStates = StreamController<SyncState>.broadcast();

  Timer? _timer;
  int _ticks = 0;
  bool _disposed = false;
  Future<void>? _runningSync;
  bool _syncAgain = false;
  bool _pullAfterSync = false;
  SyncState _syncState = const SyncState();

  Database get _db => local.db;

  // ---------------------------------------------------------------------------
  // Streams for the UI
  // ---------------------------------------------------------------------------

  /// Background sync errors that the user should know about.
  Stream<String> get errors => _errors.stream;

  SyncState get syncState => _syncState;

  Stream<SyncState> watchSyncState() async* {
    yield _syncState;
    yield* _syncStates.stream;
  }

  Stream<List<FeedPost>> watchFeed([
    FeedScope scope = const FeedScope.home(),
  ]) => _watch(() => _loadFeed(scope));

  Stream<List<Comment>> watchComments(String postId) =>
      _watch(() => _loadComments(postId));

  Stream<T> _watch<T>(Future<T> Function() load) async* {
    yield await load();
    await for (final _ in _changes.stream) {
      yield await load();
    }
  }

  // ---------------------------------------------------------------------------
  // Read (local)
  // ---------------------------------------------------------------------------

  static final _notDeleted = Finder(filter: Filter.notEquals('deleted', true));

  Future<List<FeedPost>> _loadFeed(FeedScope scope) async {
    final postRecords = await local.posts.find(_db, finder: _notDeleted);
    final hidden = (await local.hidden.findKeys(_db)).toSet();
    final visible = [
      for (final record in postRecords)
        if (scope.matches(record.value) && !hidden.contains(record.key)) record,
    ];
    final ids = {for (final record in visible) record.key};

    final reactionRecords = await local.reactions.find(
      _db,
      finder: _notDeleted,
    );
    final commentRecords = await local.comments.find(_db, finder: _notDeleted);

    final reactions = <String, Map<ReactionType, int>>{};
    final mine = <String, ReactionType>{};
    for (final record in reactionRecords) {
      final postId = record.value['post_id'] as String;
      final type = ReactionType.tryParse(record.value['type']);
      if (type == null || !ids.contains(postId)) continue;
      final counts = reactions.putIfAbsent(postId, () => {});
      counts[type] = (counts[type] ?? 0) + 1;
      if (record.value['user_id'] == userId) mine[postId] = type;
    }

    final commentCounts = <String, int>{};
    for (final record in commentRecords) {
      final postId = record.value['post_id'] as String;
      commentCounts[postId] = (commentCounts[postId] ?? 0) + 1;
    }

    final feed = visible.map((record) {
      final post = Post.fromMap(record.value);
      return FeedPost(
        post: post,
        isMine: post.userId == userId,
        reactions: reactions[post.id] ?? const {},
        comments: commentCounts[post.id] ?? 0,
        myReaction: mine[post.id],
      );
    }).toList()..sort((a, b) => b.post.createdAt.compareTo(a.post.createdAt));
    return feed;
  }

  Future<List<Comment>> _loadComments(String postId) async {
    final records = await local.comments.find(
      _db,
      finder: Finder(
        filter: Filter.and([
          Filter.equals('post_id', postId),
          Filter.notEquals('deleted', true),
        ]),
      ),
    );
    final comments = records.map((r) => Comment.fromMap(r.value)).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    // Replies to a deleted comment are deleted with it.
    final ids = {for (final c in comments) c.id};
    return [
      for (final c in comments)
        if (c.parentId == null || ids.contains(c.parentId)) c,
    ];
  }

  // ---------------------------------------------------------------------------
  // Posts: create / update / delete
  // ---------------------------------------------------------------------------

  /// Creates a post. [media] must already be uploaded (see MediaService);
  /// the text may be empty when there is media.
  Future<void> createPost(
    String content, {
    String? groupId,
    MediaRef? media,
    Post? share,
  }) async {
    final text = _validate(
      content,
      maxPostLength,
      allowEmpty: media != null || share != null,
    );
    // Sharing a share shares the original post.
    final target = share?.shareTarget;
    final id = _uuid.v4();
    final row = {
      'id': id,
      'user_id': userId,
      'username': username,
      'content': text,
      'created_at': _now(),
      'group_id': groupId,
      'media_url': media?.url,
      'media_type': media?.type.name,
      'shared_post_id': target?.id,
    };

    await _write((txn) async {
      await local.posts.record(id).put(txn, {
        ...row,
        'shared': target?.toSharedSnapshot(),
        'tags': extractTags(text),
        'avatar_url': avatarUrl,
        'updated_at': null,
        'sync_status': SyncStatus.pending.name,
        'deleted': false,
      });
      await _enqueue(
        txn,
        OutboxOperation(
          table: 'posts',
          op: OutboxOp.upsert,
          entityKey: 'posts:$id',
          data: row,
          onConflict: 'id',
        ),
      );
    });
  }

  Future<void> updatePost(String id, String content) async {
    await _write((txn) async {
      final record = await _requireOwned(txn, local.posts, id, 'post');
      final text = _validate(
        content,
        maxPostLength,
        allowEmpty:
            record['media_url'] != null || record['shared_post_id'] != null,
      );
      if (record['content'] == text) return;
      await local.posts.record(id).update(txn, {
        'content': text,
        'tags': extractTags(text),
        'updated_at': _now(),
        'sync_status': SyncStatus.pending.name,
      });
      await _enqueue(
        txn,
        OutboxOperation(
          table: 'posts',
          op: OutboxOp.update,
          entityKey: 'posts:$id',
          data: {'content': text},
          match: {'id': id},
        ),
      );
    });
  }

  /// Deletes a post. Group owners/admins may delete any post in their group
  /// ([asGroupAdmin]); the cloud checks that permission.
  Future<void> deletePost(String id, {bool asGroupAdmin = false}) async {
    await _write((txn) async {
      if (asGroupAdmin) {
        final record = await local.posts.record(id).get(txn);
        if (record == null || record['deleted'] == true) {
          throw const AppException('This post no longer exists.');
        }
      } else {
        await _requireOwned(txn, local.posts, id, 'post');
      }
      await local.posts.record(id).update(txn, {
        'deleted': true,
        'sync_status': SyncStatus.pending.name,
      });
      await _enqueue(
        txn,
        OutboxOperation(
          table: 'posts',
          op: OutboxOp.delete,
          entityKey: 'posts:$id',
          match: {'id': id},
        ),
      );
    });
  }

  /// Shows a new profile picture on all of the user's saved posts and
  /// comments at once (the cloud reads it from profiles on the next pull).
  Future<void> setMyAvatar(String? url) async {
    avatarUrl = url;
    final mine = Finder(filter: Filter.equals('user_id', userId));
    await _db.transaction((txn) async {
      await local.posts.update(txn, {'avatar_url': url}, finder: mine);
      await local.comments.update(txn, {'avatar_url': url}, finder: mine);
    });
    _notifyChanged();
  }

  /// Hides a post on this device (e.g. after reporting it).
  Future<void> hidePost(String id) async {
    await local.hidden.record(id).put(_db, {'hidden_at': _now()});
    _notifyChanged();
  }

  // ---------------------------------------------------------------------------
  // Comments: create / update / delete
  // ---------------------------------------------------------------------------

  /// Adds a comment, or a reply when [parentId] is given. [media] must
  /// already be uploaded; the text may be empty when there is media.
  Future<void> addComment(
    String postId,
    String content, {
    String? parentId,
    MediaRef? media,
  }) async {
    final text = _validate(
      content,
      maxCommentLength,
      allowEmpty: media != null,
    );
    final id = _uuid.v4();
    final row = {
      'id': id,
      'post_id': postId,
      'user_id': userId,
      'username': username,
      'content': text,
      'created_at': _now(),
      'parent_id': parentId,
      'media_url': media?.url,
      'media_type': media?.type.name,
    };

    await _write((txn) async {
      final post = await local.posts.record(postId).get(txn);
      if (post == null || post['deleted'] == true) {
        throw const AppException('This post no longer exists.');
      }
      if (parentId != null) {
        final parent = await local.comments.record(parentId).get(txn);
        if (parent == null || parent['deleted'] == true) {
          throw const AppException('That comment was deleted.');
        }
      }
      await local.comments.record(id).put(txn, {
        ...row,
        'avatar_url': avatarUrl,
        'updated_at': null,
        'sync_status': SyncStatus.pending.name,
        'deleted': false,
      });
      await _enqueue(
        txn,
        OutboxOperation(
          table: 'comments',
          op: OutboxOp.upsert,
          entityKey: 'comments:$id',
          data: row,
          onConflict: 'id',
        ),
      );
    });
  }

  Future<void> updateComment(String id, String content) async {
    await _write((txn) async {
      final record = await _requireOwned(txn, local.comments, id, 'comment');
      final text = _validate(
        content,
        maxCommentLength,
        allowEmpty: record['media_url'] != null,
      );
      if (record['content'] == text) return;
      await local.comments.record(id).update(txn, {
        'content': text,
        'updated_at': _now(),
        'sync_status': SyncStatus.pending.name,
      });
      await _enqueue(
        txn,
        OutboxOperation(
          table: 'comments',
          op: OutboxOp.update,
          entityKey: 'comments:$id',
          data: {'content': text},
          match: {'id': id},
        ),
      );
    });
  }

  Future<void> deleteComment(String id) async {
    await _write((txn) async {
      await _requireOwned(txn, local.comments, id, 'comment');
      await local.comments.record(id).update(txn, {
        'deleted': true,
        'sync_status': SyncStatus.pending.name,
      });
      await _enqueue(
        txn,
        OutboxOperation(
          table: 'comments',
          op: OutboxOp.delete,
          entityKey: 'comments:$id',
          match: {'id': id},
        ),
      );
    });
  }

  // ---------------------------------------------------------------------------
  // Reactions: set (create / change) or remove (null)
  // ---------------------------------------------------------------------------

  Future<void> setReaction(String postId, ReactionType? type) async {
    final key = LocalDatabase.reactionKey(postId, userId);

    await _write((txn) async {
      final post = await local.posts.record(postId).get(txn);
      if (post == null || post['deleted'] == true) {
        throw const AppException('This post no longer exists.');
      }

      if (type == null) {
        final existing = await local.reactions.record(key).get(txn);
        if (existing == null || existing['deleted'] == true) return;
        await local.reactions.record(key).update(txn, {
          'deleted': true,
          'sync_status': SyncStatus.pending.name,
        });
        await _enqueue(
          txn,
          OutboxOperation(
            table: 'post_reactions',
            op: OutboxOp.delete,
            entityKey: 'reactions:$key',
            match: {'post_id': postId, 'user_id': userId},
          ),
        );
        return;
      }

      final row = {'post_id': postId, 'user_id': userId, 'type': type.name};
      await local.reactions.record(key).put(txn, {
        ...row,
        'sync_status': SyncStatus.pending.name,
        'deleted': false,
      });
      await _enqueue(
        txn,
        OutboxOperation(
          table: 'post_reactions',
          op: OutboxOp.upsert,
          entityKey: 'reactions:$key',
          data: row,
          onConflict: 'post_id,user_id',
        ),
      );
    });
  }

  // ---------------------------------------------------------------------------
  // Sync: push the outbox, then pull the latest cloud data
  // ---------------------------------------------------------------------------

  /// Sends pending changes, then downloads the latest feed.
  /// Throws an [AppException] when the cloud cannot be reached.
  Future<void> refresh([FeedScope scope = const FeedScope.home()]) async {
    await sync();
    await _pull(scope);
  }

  /// Sends queued changes to the cloud in the order they were made.
  /// Never throws; problems are reported through [errors] and [syncState].
  Future<void> sync() {
    if (_disposed) return Future.value();
    final running = _runningSync;
    if (running != null) {
      // Changes made during a sync are picked up by another pass.
      _syncAgain = true;
      return running;
    }
    return _runningSync = _runSync().whenComplete(() {
      _runningSync = null;
      // Requested after the last pass had already finished.
      if (_syncAgain) unawaited(sync());
    });
  }

  Future<void> _runSync() async {
    await _publishSyncState(isSyncing: true);
    try {
      do {
        _syncAgain = false;
        await _flushOutbox();
      } while (_syncAgain && !_disposed);

      if (_pullAfterSync && !_disposed) {
        _pullAfterSync = false;
        try {
          await _pull(const FeedScope.home());
        } on AppException {
          // Already reflected in the sync state.
        }
      }
    } catch (error) {
      _reportError('Sync failed: ${AppException.from(error).message}');
    } finally {
      await _publishSyncState(isSyncing: false);
    }
  }

  Future<void> _flushOutbox() async {
    final first = Finder(sortOrders: [SortOrder(Field.key)]);
    while (!_disposed) {
      final record = await local.outbox.findFirst(_db, finder: first);
      if (record == null) {
        await _publishSyncState(isOffline: false, clearError: true);
        return;
      }
      final operation = OutboxOperation.fromMap(record.key, record.value);

      try {
        await remote.apply(operation);
      } catch (error) {
        final failure = AppException.from(error);
        if (failure.isTransient) {
          // Keep the operation and try again later.
          await local.outbox.record(record.key).update(_db, {
            'attempts': operation.attempts + 1,
            'last_error': failure.message,
          });
          await _publishSyncState(isOffline: true, lastError: failure.message);
          return;
        }
        await _discardFailedChange(operation, failure);
        continue;
      }

      await _completeOperation(operation);
    }
  }

  /// The cloud accepted [operation]: remove it from the outbox and mark the
  /// row as synced once nothing else is queued for it.
  Future<void> _completeOperation(OutboxOperation operation) async {
    await _db.transaction((txn) async {
      await local.outbox.record(operation.key!).delete(txn);
      if (await _hasQueuedOperations(txn, operation.entityKey)) return;

      final (store, id) = _entity(operation.entityKey);
      final row = await store.record(id).get(txn);
      if (row == null) return;

      if (row['deleted'] == true) {
        await store.record(id).delete(txn);
        if (store == local.posts) {
          final ofPost = Finder(filter: Filter.equals('post_id', id));
          await local.comments.delete(txn, finder: ofPost);
          await local.reactions.delete(txn, finder: ofPost);
        } else if (store == local.comments) {
          // The cloud deletes replies with their parent (ON DELETE CASCADE).
          await local.comments.delete(
            txn,
            finder: Finder(filter: Filter.equals('parent_id', id)),
          );
        }
      } else {
        await store.record(id).update(txn, {
          'sync_status': SyncStatus.synced.name,
        });
      }
    });
    _notifyChanged();
  }

  /// The cloud rejected a change permanently (permission, constraint, ...).
  /// Drop every queued operation for that row and restore it from the cloud.
  Future<void> _discardFailedChange(
    OutboxOperation operation,
    AppException failure,
  ) async {
    var rowStillShown = false;
    await _db.transaction((txn) async {
      await local.outbox.delete(
        txn,
        finder: Finder(
          filter: Filter.equals('entity_key', operation.entityKey),
        ),
      );
      final (store, id) = _entity(operation.entityKey);
      final row = await store.record(id).get(txn);
      if (row != null) {
        rowStillShown = true;
        // Marked as synced so the next pull replaces (or removes) it with
        // the cloud version.
        await store.record(id).update(txn, {
          'sync_status': SyncStatus.synced.name,
          'deleted': false,
        });
      }
    });
    _pullAfterSync = true;
    _notifyChanged();
    if (rowStillShown) {
      _reportError('Could not save your change: ${failure.message}');
    }
  }

  static const pageSize = 50;

  Future<void> _pull(FeedScope scope) async {
    final rows = await _fetch(scope);
    final serverIds = {for (final row in rows) row['id'] as String};
    // When a full page came back, only the time range it covers is known;
    // older cached posts (from "load more") are kept.
    final DateTime? oldest = rows.length < pageSize
        ? null
        : DateTime.parse(rows.last['created_at'] as String);

    await _db.transaction((txn) async {
      // Unchanged posts in this scope that the cloud no longer returns were
      // deleted (or hidden, e.g. after a block): drop them.
      final synced = await local.posts.find(
        txn,
        finder: Finder(
          filter: Filter.equals('sync_status', SyncStatus.synced.name),
        ),
      );
      for (final record in synced) {
        if (!scope.matches(record.value) || serverIds.contains(record.key)) {
          continue;
        }
        final created = DateTime.tryParse('${record.value['created_at']}');
        if (oldest != null && created != null && created.isBefore(oldest)) {
          continue;
        }
        await record.ref.delete(txn);
        await _deleteSyncedChildren(txn, record.key);
      }
      await _storeRows(txn, rows);
    });

    _notifyChanged();
    await _publishSyncState(isOffline: false, clearError: true);
  }

  /// Loads the page of posts older than the oldest one shown in [scope].
  /// Returns false when there is nothing older.
  Future<bool> loadMore(FeedScope scope) async {
    final cached = await _loadFeed(scope);
    if (cached.isEmpty) return false;
    final rows = await _fetch(scope, before: cached.last.post.createdAt);
    await _db.transaction((txn) => _storeRows(txn, rows));
    _notifyChanged();
    return rows.length >= pageSize;
  }

  Future<List<Map<String, dynamic>>> _fetch(
    FeedScope scope, {
    DateTime? before,
  }) async {
    try {
      return await remote.fetchFeed(scope, limit: pageSize, before: before);
    } catch (error) {
      final failure = AppException.from(error);
      await _publishSyncState(
        isOffline: failure.isTransient,
        lastError: failure.message,
      );
      throw failure;
    }
  }

  /// Saves cloud posts with their comments and reactions, keeping rows that
  /// have unsent local changes.
  Future<void> _storeRows(
    Transaction txn,
    List<Map<String, dynamic>> rows,
  ) async {
    for (final post in rows) {
      final id = post['id'] as String;
      final shared = post['shared'] as Map?;
      await _putUnlessPending(txn, local.posts, id, {
        'id': id,
        'user_id': post['user_id'],
        'username': post['username'],
        'content': post['content'],
        'created_at': post['created_at'],
        'updated_at': post['updated_at'],
        'group_id': post['group_id'],
        'media_url': post['media_url'],
        'media_type': post['media_type'],
        'tags': post['tags'] ?? extractTags('${post['content'] ?? ''}'),
        'avatar_url': _authorAvatar(post),
        'shared_post_id': post['shared_post_id'],
        'shared': shared == null
            ? null
            : (Map<String, Object?>.from(shared)
                ..['avatar_url'] = _authorAvatar(shared)
                ..remove('author')),
      });

      await _deleteSyncedChildren(txn, id);
      for (final comment in (post['comments'] as List? ?? const [])) {
        final c = Map<String, Object?>.from(comment as Map)
          ..['avatar_url'] = _authorAvatar(comment)
          ..remove('author');
        await _putUnlessPending(txn, local.comments, c['id'] as String, c);
      }
      for (final reaction in (post['post_reactions'] as List? ?? const [])) {
        final r = Map<String, Object?>.from(reaction as Map);
        final key = LocalDatabase.reactionKey(
          r['post_id'] as String,
          r['user_id'] as String,
        );
        await _putUnlessPending(txn, local.reactions, key, r);
      }
    }
  }

  /// Removes another user's cached posts and comments (e.g. after blocking).
  Future<void> removeUserContent(String otherUserId) async {
    final theirs = Finder(
      filter: Filter.and([
        Filter.equals('user_id', otherUserId),
        Filter.equals('sync_status', SyncStatus.synced.name),
      ]),
    );
    await _db.transaction((txn) async {
      for (final key in await local.posts.findKeys(txn, finder: theirs)) {
        await local.posts.record(key).delete(txn);
        await _deleteSyncedChildren(txn, key);
      }
      await local.comments.delete(txn, finder: theirs);
      await local.reactions.delete(txn, finder: theirs);
    });
    _notifyChanged();
  }

  static String? _authorAvatar(Map row) =>
      (row['author'] as Map?)?['profile_url'] as String?;

  Future<void> _deleteSyncedChildren(Transaction txn, String postId) async {
    final finder = Finder(
      filter: Filter.and([
        Filter.equals('post_id', postId),
        Filter.equals('sync_status', SyncStatus.synced.name),
      ]),
    );
    await local.comments.delete(txn, finder: finder);
    await local.reactions.delete(txn, finder: finder);
  }

  /// Rows changed on this device win over the cloud copy until they are sent.
  Future<void> _putUnlessPending(
    Transaction txn,
    StoreRef<String, Map<String, Object?>> store,
    String key,
    Map<String, Object?> value,
  ) async {
    final existing = await store.record(key).get(txn);
    if (existing?['sync_status'] == SyncStatus.pending.name) return;
    await store.record(key).put(txn, {
      ...value,
      'sync_status': SyncStatus.synced.name,
      'deleted': false,
    });
  }

  void _onTick() {
    if (_disposed) return;
    _ticks++;
    if (_syncState.pendingChanges > 0) {
      unawaited(sync());
    } else if (_ticks % 3 == 0) {
      // Pick up other people's posts now and then.
      unawaited(_pull(const FeedScope.home()).catchError((_) {}));
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Runs a local write in a transaction, then refreshes the UI and starts a
  /// sync in the background.
  Future<void> _write(Future<void> Function(Transaction txn) action) async {
    if (_disposed) throw const AppException('You have been signed out.');
    try {
      await _db.transaction(action);
    } on AppException {
      rethrow;
    } catch (error) {
      throw AppException('Could not save on this device: $error', cause: error);
    }
    _notifyChanged();
    await _publishSyncState();
    unawaited(sync());
  }

  Future<void> _enqueue(Transaction txn, OutboxOperation operation) =>
      local.outbox.add(txn, operation.toMap());

  Future<bool> _hasQueuedOperations(Transaction txn, String entityKey) async =>
      await local.outbox.count(
        txn,
        filter: Filter.equals('entity_key', entityKey),
      ) >
      0;

  (StoreRef<String, Map<String, Object?>>, String) _entity(String entityKey) {
    final separator = entityKey.indexOf(':');
    final id = entityKey.substring(separator + 1);
    return switch (entityKey.substring(0, separator)) {
      'posts' => (local.posts, id),
      'comments' => (local.comments, id),
      _ => (local.reactions, id),
    };
  }

  Future<Map<String, Object?>> _requireOwned(
    Transaction txn,
    StoreRef<String, Map<String, Object?>> store,
    String id,
    String what,
  ) async {
    final record = await store.record(id).get(txn);
    if (record == null || record['deleted'] == true) {
      throw AppException('This $what no longer exists.');
    }
    if (record['user_id'] != userId) {
      throw AppException('You can only change your own $what.');
    }
    return record;
  }

  String _validate(String content, int maxLength, {bool allowEmpty = false}) {
    final text = content.trim();
    if (text.isEmpty && !allowEmpty) {
      throw const ValidationException('Write something first.');
    }
    if (text.length > maxLength) {
      throw ValidationException(
        'Too long: ${text.length}/$maxLength characters.',
      );
    }
    return text;
  }

  String _now() => DateTime.now().toUtc().toIso8601String();

  Future<void> _publishSyncState({
    bool? isSyncing,
    bool? isOffline,
    String? lastError,
    bool clearError = false,
  }) async {
    if (_disposed) return;
    final pending = await local.outbox.count(_db);
    _syncState = _syncState.copyWith(
      pendingChanges: pending,
      isSyncing: isSyncing,
      isOffline: isOffline,
      lastError: lastError,
      clearError: clearError,
    );
    if (!_syncStates.isClosed) _syncStates.add(_syncState);
  }

  void _notifyChanged() {
    if (!_changes.isClosed) _changes.add(null);
  }

  void _reportError(String message) {
    if (!_errors.isClosed) _errors.add(message);
  }

  Future<void> dispose() async {
    _disposed = true;
    _timer?.cancel();
    await _changes.close();
    await _errors.close();
    await _syncStates.close();
    await local.close();
  }
}
