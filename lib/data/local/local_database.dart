import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';
import 'package:sembast_web/sembast_web.dart';

/// Local schema (sembast document stores, one database file per user).
///
/// posts      key: post id (uuid)
///   { id, user_id, username, content, created_at, updated_at,
///     group_id, media_url, media_type, tags: [string],
///     sync_status: 'synced'|'pending', deleted: bool }
/// comments   key: comment id (uuid)
///   { id, post_id, parent_id, user_id, username, avatar_url, content,
///     media_url, media_type, created_at, updated_at, sync_status, deleted }
/// reactions  key: `<post_id>|<user_id>`
///   { post_id, user_id, type: 'like'|'dislike', sync_status, deleted }
/// outbox     key: auto-increment int (send order)
///   { table, op: 'upsert'|'update'|'delete', data, match, on_conflict,
///     entity_key, attempts, last_error, created_at }
/// hidden     key: post id  { hidden_at }  (reported posts)
///
/// Rows deleted on this device are kept with `deleted: true` until the cloud
/// confirms the delete, so a refresh cannot bring them back in the meantime.
class LocalDatabase {
  LocalDatabase(this.db);

  static const _version = 1;

  final Database db;

  final posts = stringMapStoreFactory.store('posts');
  final comments = stringMapStoreFactory.store('comments');
  final reactions = stringMapStoreFactory.store('reactions');
  final outbox = intMapStoreFactory.store('outbox');

  /// Posts the user chose not to see (e.g. reported), keyed by post id.
  final hidden = stringMapStoreFactory.store('hidden');

  /// Opens the database for [userId] on the current platform: IndexedDB on
  /// the web, a file in the app support directory elsewhere.
  static Future<LocalDatabase> open(String userId) async {
    final name = 'appsocial_$userId.db';
    if (kIsWeb) {
      return LocalDatabase(
        await databaseFactoryWeb.openDatabase(name, version: _version),
      );
    }
    final dir = await getApplicationSupportDirectory();
    return LocalDatabase(
      await databaseFactoryIo.openDatabase(
        p.join(dir.path, name),
        version: _version,
      ),
    );
  }

  /// Opens a database with an explicit [factory] (used by tests).
  static Future<LocalDatabase> openWith(
    DatabaseFactory factory,
    String name,
  ) async => LocalDatabase(await factory.openDatabase(name, version: _version));

  static String reactionKey(String postId, String userId) => '$postId|$userId';

  Future<void> close() => db.close();
}
