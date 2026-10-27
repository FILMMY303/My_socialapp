import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/app_exception.dart';
import '../../core/notifications/browser_notifications.dart';
import '../models/models.dart';

/// The notifications page: follows, follow requests, and new posts from
/// people and pages you follow. Rows are created by database triggers;
/// this service reads them and listens for new ones (online only).
class ActivityService {
  ActivityService(
    this._client,
    this.userId, {
    this._browser = const BrowserNotifications(),
  });

  static const _columns =
      'id, type, post_id, group_id, is_read, created_at, '
      'actor:profiles(id, username, display_name, profile_url, is_private), '
      'post:posts(content, media_type), '
      'group:groups(name, avatar_url)';

  final SupabaseClient _client;
  final String userId;
  final BrowserNotifications _browser;
  final _events = StreamController<ActivityNotification>.broadcast();
  RealtimeChannel? _channel;

  /// Unread count for the bell badge.
  final unread = ValueNotifier<int>(0);

  /// New notifications while the app is visible (for the in-app banner).
  Stream<ActivityNotification> get events => _events.stream;

  /// Called when the user taps a browser notification.
  void Function(ActivityNotification notification)? onOpen;

  void start() {
    if (_channel != null) return;
    _channel = _client
        .channel('activity-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) => _onInsert(payload.newRecord['id'] as String?),
        )
        // Also runs after a reconnect, catching rows missed while offline.
        .subscribe((status, _) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            unawaited(refreshUnread().catchError((_) {}));
          }
        });
    _lifecycle = AppLifecycleListener(
      onResume: () => unawaited(refreshUnread().catchError((_) {})),
    );
    unawaited(refreshUnread().catchError((_) {}));
  }

  AppLifecycleListener? _lifecycle;

  Future<void> _onInsert(String? id) async {
    if (id == null) return;
    unread.value++;
    final ActivityNotification? notification;
    try {
      notification = await _get(id);
    } catch (_) {
      return;
    }
    if (notification == null) return;
    if (_browser.isPageVisible) {
      if (!_events.isClosed) _events.add(notification);
    } else {
      _browser.show(
        title: notification.displayName,
        body: notification.text,
        icon: notification.displayAvatarUrl,
        tag: 'activity-${notification.id}',
        onClick: () => onOpen?.call(notification!),
      );
    }
  }

  Future<ActivityNotification?> _get(String id) async {
    final row = await runOnline(
      () => _client
          .from('notifications')
          .select(_columns)
          .eq('id', id)
          .maybeSingle(),
    );
    return row == null ? null : ActivityNotification.fromMap(row);
  }

  Future<List<ActivityNotification>> list() async {
    final rows = await runOnline(
      () => _client
          .from('notifications')
          .select(_columns)
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(100),
    );
    return [for (final row in rows) ?ActivityNotification.fromMap(row)];
  }

  Future<void> refreshUnread() async {
    final result = await runOnline(
      () => _client
          .from('notifications')
          .select('id')
          .eq('user_id', userId)
          .eq('is_read', false)
          .count(CountOption.exact),
    );
    unread.value = result.count;
  }

  Future<void> markAllRead() async {
    if (unread.value == 0) return;
    await runOnline(
      () => _client
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', userId)
          .eq('is_read', false),
    );
    unread.value = 0;
  }

  Future<void> delete(ActivityNotification notification) => runOnline(
    () => _client.from('notifications').delete().eq('id', notification.id),
  );

  void dispose() {
    _lifecycle?.dispose();
    final channel = _channel;
    if (channel != null) unawaited(_client.removeChannel(channel));
    _events.close();
    unread.dispose();
  }
}
