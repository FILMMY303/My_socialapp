import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/app_exception.dart';
import '../../core/notifications/browser_notifications.dart';
import '../models/models.dart';
import 'profile_service.dart';

/// A new direct message to tell the user about.
class DmNotification {
  const DmNotification({required this.sender, required this.message});

  final Profile sender;
  final ChatMessage message;

  String get preview => message.text.isNotEmpty
      ? message.text
      : message.media?.type == MediaType.video
      ? 'Sent a video'
      : 'Sent a photo';
}

/// Decides whether an incoming DM should notify, and keeps the mute list.
/// Contains no Supabase code so it can be unit tested.
class DmNotifier {
  DmNotifier({
    required this.userId,
    required this._loadProfile,
    this._browser = const BrowserNotifications(),
  });

  final String userId;
  final Future<Profile> Function(String id) _loadProfile;
  final BrowserNotifications _browser;
  final _events = StreamController<DmNotification>.broadcast();

  /// People whose messages don't notify. Listen to update mute buttons.
  final muted = ValueNotifier<Set<String>>(const {});

  /// The partner of the chat currently on screen (no alert for that chat).
  String? activeChatPartnerId;

  /// Called when the user taps a browser notification.
  void Function(Profile sender)? onOpenChat;

  /// In-app alerts (shown while the app is visible).
  Stream<DmNotification> get events => _events.stream;

  bool isMuted(String partnerId) => muted.value.contains(partnerId);

  Future<void> handleIncoming(ChatMessage message) async {
    if (message.receiverId != userId || message.senderId == userId) return;
    if (isMuted(message.senderId)) return;
    if (message.senderId == activeChatPartnerId && _browser.isPageVisible) {
      return;
    }

    Profile sender;
    try {
      sender = await _loadProfile(message.senderId);
    } catch (_) {
      sender = Profile(id: message.senderId, username: 'Someone');
    }
    final notification = DmNotification(sender: sender, message: message);

    if (_browser.isPageVisible) {
      if (!_events.isClosed) _events.add(notification);
    } else {
      _browser.show(
        title: sender.name,
        body: notification.preview,
        icon: sender.avatarUrl,
        tag: 'dm-${sender.id}',
        onClick: () => onOpenChat?.call(sender),
      );
    }
  }

  void dispose() {
    _events.close();
    muted.dispose();
  }
}

/// Live DM notifications and per-person mutes (online only).
class NotificationService extends DmNotifier {
  NotificationService(this._client, String userId, ProfileService profiles)
    : super(userId: userId, loadProfile: profiles.getProfile);

  final SupabaseClient _client;
  RealtimeChannel? _channel;

  BrowserNotifications get browser => _browser;

  /// Starts listening for messages sent to the user and loads the mutes.
  void start() {
    if (_channel != null) return;
    _channel = _client
        .channel('dm-notifications-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'direct_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'receiver_id',
            value: userId,
          ),
          callback: (payload) =>
              handleIncoming(ChatMessage.fromMap(payload.newRecord)),
        )
        .subscribe();
    unawaited(loadMutes().catchError((_) {}));
  }

  Future<void> loadMutes() async {
    final rows = await runOnline(
      () => _client
          .from('chat_mutes')
          .select('muted_user_id')
          .eq('user_id', userId),
    );
    muted.value = {for (final r in rows) r['muted_user_id'] as String};
  }

  /// Turns notifications from [partnerId] off or on.
  Future<void> setMuted(String partnerId, bool mute) async {
    final before = muted.value;
    // Update the UI at once; undo if the cloud rejects it.
    muted.value = mute
        ? {...before, partnerId}
        : ({...before}..remove(partnerId));
    try {
      if (mute) {
        await runOnline(
          () => _client
              .from('chat_mutes')
              .upsert(
                {'user_id': userId, 'muted_user_id': partnerId},
                onConflict: 'user_id,muted_user_id',
                ignoreDuplicates: true,
              ),
        );
      } else {
        await runOnline(
          () => _client
              .from('chat_mutes')
              .delete()
              .eq('user_id', userId)
              .eq('muted_user_id', partnerId),
        );
      }
    } catch (error) {
      muted.value = before;
      rethrow;
    }
  }

  @override
  void dispose() {
    final channel = _channel;
    if (channel != null) unawaited(_client.removeChannel(channel));
    super.dispose();
  }
}
