import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/app_exception.dart';
import '../models/models.dart';
import 'profile_service.dart';

/// 1-1 chat with live updates (online only).
class ChatService {
  ChatService(this._client, this.userId, this._profiles);

  static const maxLength = 4000;

  final SupabaseClient _client;
  final String userId;
  final ProfileService _profiles;
  final _profileCache = <String, Profile>{};

  /// Every message the user sent or received, oldest first, updated live.
  /// Row-level security limits the rows to the user's own conversations.
  Stream<List<ChatMessage>> _allMessages() => _client
      .from('direct_messages')
      .stream(primaryKey: ['id'])
      // Newest first, so the limit keeps the latest 1000 messages...
      .order('created_at', ascending: false)
      .limit(1000)
      // ...then oldest first for display.
      .map(
        (rows) =>
            rows.map(ChatMessage.fromMap).toList()
              ..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
      );

  /// Unread messages sent to the user, updated live.
  Stream<List<ChatMessage>> watchUnread() => _allMessages().map(
    (messages) =>
        messages.where((m) => m.receiverId == userId && !m.isRead).toList(),
  );

  Stream<List<ChatMessage>> watchConversation(String partnerId) =>
      _allMessages().map(
        (messages) =>
            messages.where((m) => m.partnerOf(userId) == partnerId).toList(),
      );

  /// Latest message per partner, newest conversation first.
  Stream<List<Conversation>> watchConversations() =>
      _allMessages().asyncMap((messages) async {
        final latest = <String, ChatMessage>{};
        final unread = <String, int>{};
        for (final message in messages) {
          final partner = message.partnerOf(userId);
          latest[partner] = message;
          if (message.receiverId == userId && !message.isRead) {
            unread[partner] = (unread[partner] ?? 0) + 1;
          }
        }
        // Reload partners each time so new names/pictures show up; fall back
        // to the last known profiles if the request fails.
        try {
          for (final profile in await _profiles.getProfiles(latest.keys)) {
            _profileCache[profile.id] = profile;
          }
        } on AppException {
          if (latest.keys.any((id) => !_profileCache.containsKey(id))) rethrow;
        }
        final conversations =
            [
              for (final entry in latest.entries)
                Conversation(
                  partner:
                      _profileCache[entry.key] ??
                      Profile(id: entry.key, username: 'Unknown user'),
                  lastMessage: entry.value,
                  unread: unread[entry.key] ?? 0,
                ),
            ]..sort(
              (a, b) =>
                  b.lastMessage.createdAt.compareTo(a.lastMessage.createdAt),
            );
        return conversations;
      });

  Future<void> send(String partnerId, String text, {MediaRef? media}) async {
    final message = text.trim();
    if (message.isEmpty && media == null) {
      throw const ValidationException('Write a message first.');
    }
    if (message.length > maxLength) {
      throw const ValidationException('Message is too long (max 4000).');
    }
    if (partnerId == userId) {
      throw const ValidationException("You can't message yourself.");
    }
    await runOnline(
      () => _client.from('direct_messages').insert({
        'sender_id': userId,
        'receiver_id': partnerId,
        'message': message,
        'media_url': media?.url,
        'media_type': media?.type.name,
      }),
    );
  }

  Future<void> markRead(String partnerId) => runOnline(
    () => _client
        .from('direct_messages')
        .update({'is_read': true})
        .eq('sender_id', partnerId)
        .eq('receiver_id', userId)
        .eq('is_read', false),
  );

  /// Deletes a message the user sent.
  Future<void> unsend(ChatMessage message) async {
    if (message.senderId != userId) {
      throw const AppException('You can only unsend your own messages.');
    }
    await runOnline(
      () => _client.from('direct_messages').delete().eq('id', message.id),
    );
    if (message.media != null) {
      try {
        await _client.storage.from('chat-media').remove([message.media!.url]);
      } catch (_) {
        // The message is gone; a leftover file is harmless.
      }
    }
  }
}
