import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/time_ago.dart';
import '../../data/models/models.dart';
import '../../data/repository_scope.dart';
import '../../data/services/chat_service.dart';
import '../../data/services/notification_service.dart';
import '../navigation.dart';
import '../widgets/common_widgets.dart';
import '../widgets/media_view.dart';

/// 1-1 conversation with text, photos and videos, updated live.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.partner});

  final Profile partner;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _text = TextEditingController();
  Stream<List<ChatMessage>>? _messages;
  bool _sending = false;
  String _status = '';
  int _lastMarkedCount = -1;

  AppServices get _services => RepositoryScope.servicesOf(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_messages == null) {
      _messages = _services.chat.watchConversation(widget.partner.id);
      // No alerts for the chat that is already open.
      _notifications = _services.notifications
        ..activeChatPartnerId = widget.partner.id;
    }
  }

  NotificationService? _notifications;

  @override
  void dispose() {
    if (_notifications?.activeChatPartnerId == widget.partner.id) {
      _notifications!.activeChatPartnerId = null;
    }
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _toggleMute(bool mute) async {
    try {
      await _services.notifications.setMuted(widget.partner.id, mute);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mute
                ? "You won't be notified about messages from "
                      '${widget.partner.name}.'
                : 'Notifications from ${widget.partner.name} are on.',
          ),
        ),
      );
    } catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    }
  }

  final _scroll = ScrollController();
  int _shownCount = 0;

  /// Jumps to the newest message when the chat opens or a message arrives.
  void _scrollToBottomOnNew(int count) {
    if (count <= _shownCount) {
      _shownCount = count;
      return;
    }
    final first = _shownCount == 0;
    _shownCount = count;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final end = _scroll.position.maxScrollExtent;
      if (first) {
        _scroll.jumpTo(end);
      } else {
        _scroll.animateTo(
          end,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _markReadIfNeeded(List<ChatMessage> messages) {
    final unread = messages
        .where((m) => m.receiverId == _services.userId && !m.isRead)
        .length;
    if (unread == 0 || unread == _lastMarkedCount) return;
    _lastMarkedCount = unread;
    _services.chat.markRead(widget.partner.id).catchError((_) {});
  }

  Future<void> _send({MediaType? attach}) async {
    final services = _services;
    setState(() => _sending = true);
    try {
      MediaRef? media;
      if (attach != null) {
        final file = await services.media.pick(attach);
        if (file == null) return;
        setState(() => _status = 'Uploading ${attach.name}…');
        media = await services.media.uploadChatMedia(
          file,
          attach,
          widget.partner.id,
        );
      }
      await services.chat.send(
        widget.partner.id,
        attach == null ? _text.text : '',
        media: media,
      );
      if (attach == null) _text.clear();
    } catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _status = '';
        });
      }
    }
  }

  Future<void> _unsend(ChatMessage message) async {
    final confirmed = await confirmDelete(context, 'message');
    if (!confirmed || !mounted) return;
    try {
      await _services.chat.unsend(message);
    } catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = _services.userId;
    return Scaffold(
      backgroundColor: kCream,
      appBar: AppBar(
        backgroundColor: kCream,
        titleSpacing: 0,
        actions: [
          ValueListenableBuilder<Set<String>>(
            valueListenable: _services.notifications.muted,
            builder: (context, muted, _) {
              final isMuted = muted.contains(widget.partner.id);
              return IconButton(
                tooltip: isMuted
                    ? 'Turn on notifications'
                    : 'Mute notifications',
                onPressed: () => _toggleMute(!isMuted),
                icon: Icon(
                  isMuted
                      ? Icons.notifications_off_outlined
                      : Icons.notifications_active_outlined,
                  color: isMuted ? kMuted : kGreen,
                ),
              );
            },
          ),
        ],
        title: InkWell(
          onTap: () => openProfile(context, widget.partner.id),
          child: Row(
            children: [
              UserAvatar(
                name: widget.partner.name,
                url: widget.partner.avatarUrl,
                radius: 18,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  widget.partner.name,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              stream: _messages,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return ErrorRetry(
                    message: errorMessage(snapshot.error!),
                    onRetry: () => setState(
                      () => _messages = _services.chat.watchConversation(
                        widget.partner.id,
                      ),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: kGreen),
                  );
                }
                final messages = snapshot.data!;
                _markReadIfNeeded(messages);
                if (messages.isEmpty) {
                  return Center(
                    child: Text(
                      'Say hi to ${widget.partner.name} 👋',
                      style: TextStyle(color: kSecondaryText),
                    ),
                  );
                }
                _scrollToBottomOnNew(messages.length);
                // Oldest at the top, newest at the bottom.
                return ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final mine = message.senderId == me;
                    return _Bubble(
                      key: ValueKey(message.id),
                      message: message,
                      mine: mine,
                      onLongPress: mine ? () => _unsend(message) : null,
                    );
                  },
                );
              },
            ),
          ),
          if (_status.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                _status,
                style: TextStyle(color: kSecondaryText, fontSize: 12),
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Send photo',
                    onPressed: _sending
                        ? null
                        : () => _send(attach: MediaType.image),
                    icon: const Icon(Icons.image_outlined, color: kGreen),
                  ),
                  IconButton(
                    tooltip: 'Send video',
                    onPressed: _sending
                        ? null
                        : () => _send(attach: MediaType.video),
                    icon: const Icon(Icons.videocam_outlined, color: kGreen),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _text,
                      enabled: !_sending,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: ChatService.maxLength,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: 'Message…',
                        counterText: '',
                        filled: true,
                        fillColor: kCardWhite,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Send',
                    onPressed: _sending ? null : () => _send(),
                    icon: _sending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded, color: kGreen),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    super.key,
    required this.message,
    required this.mine,
    this.onLongPress,
  });

  final ChatMessage message;
  final bool mine;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final media = RepositoryScope.servicesOf(context).media;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        onSecondaryTap: onLongPress,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.72,
          ),
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: mine ? kGreen : kCardWhite,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: mine
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              if (message.media != null)
                _ChatMedia(
                  load: () => media.chatMediaUrl(message.media!.url),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return const Text('Could not load attachment');
                    }
                    if (!snapshot.hasData) {
                      return const SizedBox(
                        height: 120,
                        width: 160,
                        child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    }
                    return MediaView(
                      url: snapshot.data!,
                      type: message.media!.type,
                      maxHeight: 260,
                      borderRadius: 12,
                    );
                  },
                ),
              if (message.text.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(top: message.media != null ? 6 : 0),
                  child: Text(
                    message.text,
                    style: TextStyle(color: mine ? kWhite : kMainText),
                  ),
                ),
              const SizedBox(height: 2),
              Text(
                '${timeAgo(message.createdAt)}'
                '${mine && message.isRead ? ' · Seen' : ''}',
                style: TextStyle(
                  fontSize: 10,
                  color: mine ? Colors.white70 : kMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Resolves the signed URL once per bubble instead of on every rebuild.
class _ChatMedia extends StatefulWidget {
  const _ChatMedia({required this.load, required this.builder});

  final Future<String> Function() load;
  final AsyncWidgetBuilder<String> builder;

  @override
  State<_ChatMedia> createState() => _ChatMediaState();
}

class _ChatMediaState extends State<_ChatMedia> {
  late final Future<String> _url = widget.load();

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<String>(future: _url, builder: widget.builder);
}
