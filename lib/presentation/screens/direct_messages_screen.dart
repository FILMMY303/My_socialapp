import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/time_ago.dart';
import '../../data/models/models.dart';
import '../../data/repository_scope.dart';
import '../navigation.dart';
import '../widgets/common_widgets.dart';
import '../widgets/media_view.dart';
import 'follow_list_screen.dart';

/// Conversations, newest first, updated live.
class DirectMessagesScreen extends StatefulWidget {
  const DirectMessagesScreen({super.key});

  @override
  State<DirectMessagesScreen> createState() => _DirectMessagesScreenState();
}

class _DirectMessagesScreenState extends State<DirectMessagesScreen> {
  Stream<List<Conversation>>? _stream;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _stream ??= RepositoryScope.servicesOf(context).chat.watchConversations();
  }

  void _retry() => setState(
    () =>
        _stream = RepositoryScope.servicesOf(context).chat.watchConversations(),
  );

  Future<void> _newMessage() async {
    final services = RepositoryScope.servicesOf(context);
    final partner = await showModalBottomSheet<Profile>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kCream,
      builder: (_) =>
          RepositoryScope(services: services, child: const _PickUserSheet()),
    );
    if (partner != null && mounted) await openChat(context, partner);
  }

  @override
  Widget build(BuildContext context) {
    final services = RepositoryScope.servicesOf(context);
    final me = services.userId;
    final notifications = services.notifications;
    return Scaffold(
      backgroundColor: kCream,
      appBar: AppBar(
        backgroundColor: kCream,
        title: const Text('Messages'),
        actions: [
          IconButton(
            tooltip: 'New message',
            onPressed: _newMessage,
            icon: const Icon(Icons.edit_square),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Conversation>>(
              stream: _stream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return ErrorRetry(
                    message: errorMessage(snapshot.error!),
                    onRetry: _retry,
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: kGreen),
                  );
                }
                final conversations = snapshot.data!;
                if (conversations.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'No messages yet.',
                          style: TextStyle(color: kSecondaryText),
                        ),
                        TextButton(
                          onPressed: _newMessage,
                          child: const Text('Start a conversation'),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: conversations.length,
                  itemBuilder: (context, index) {
                    final c = conversations[index];
                    final last = c.lastMessage;
                    final preview = last.text.isNotEmpty
                        ? last.text
                        : last.media?.type == MediaType.video
                        ? '🎬 Video'
                        : '📷 Photo';
                    return ListTile(
                      onTap: () => openChat(context, c.partner),
                      leading: UserAvatar(
                        name: c.partner.name,
                        url: c.partner.avatarUrl,
                      ),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(
                              c.partner.name,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: c.unread > 0
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                              ),
                            ),
                          ),
                          ValueListenableBuilder<Set<String>>(
                            valueListenable: notifications.muted,
                            builder: (context, muted, _) =>
                                muted.contains(c.partner.id)
                                ? Padding(
                                    padding: EdgeInsets.only(left: 4),
                                    child: Tooltip(
                                      message: 'Notifications muted',
                                      child: Icon(
                                        Icons.notifications_off_outlined,
                                        size: 15,
                                        color: kMuted,
                                      ),
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ),
                      subtitle: Text(
                        '${last.senderId == me ? 'You: ' : ''}$preview',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            timeAgo(last.createdAt),
                            style: TextStyle(fontSize: 11, color: kMuted),
                          ),
                          if (c.unread > 0)
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: kGreen,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${c.unread}',
                                style: const TextStyle(
                                  color: kWhite,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PickUserSheet extends StatefulWidget {
  const _PickUserSheet();

  @override
  State<_PickUserSheet> createState() => _PickUserSheetState();
}

class _PickUserSheetState extends State<_PickUserSheet> {
  Future<List<Profile>>? _results;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _search(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      final services = RepositoryScope.servicesOf(context);
      setState(() {
        _results = services.profiles
            .searchUsers(query)
            .then((l) => l.where((p) => p.id != services.userId).toList());
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                autofocus: true,
                onChanged: _search,
                decoration: InputDecoration(
                  hintText: 'Search people to message',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: kCardWhite,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(
              child: _results == null
                  ? const SizedBox.shrink()
                  : FutureBuilder<List<Profile>>(
                      future: _results,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Center(
                            child: Text(
                              errorMessage(snapshot.error!),
                              style: const TextStyle(color: kRed),
                            ),
                          );
                        }
                        if (!snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(color: kGreen),
                          );
                        }
                        final people = snapshot.data!;
                        if (people.isEmpty) {
                          return const Center(child: Text('No one found.'));
                        }
                        return ListView(
                          children: [
                            for (final p in people)
                              ProfileTile(
                                profile: p,
                                onTap: () => Navigator.of(context).pop(p),
                              ),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
