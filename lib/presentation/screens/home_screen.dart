import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/models.dart';
import '../../data/repository_scope.dart';
import '../widgets/common_widgets.dart';
import '../widgets/feed_list.dart';
import '../widgets/media_view.dart';
import 'activity_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.onOpenComposer,
    required this.onOpenMessages,
  });

  final VoidCallback onOpenComposer;
  final VoidCallback onOpenMessages;

  @override
  Widget build(BuildContext context) {
    final services = RepositoryScope.servicesOf(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Row(
              children: [
                const Expanded(child: BrandHeader()),
                _MessagesButton(onTap: onOpenMessages),
                const SizedBox(width: 10),
                ValueListenableBuilder<int>(
                  valueListenable: services.activity.unread,
                  builder: (context, unread, _) => Stack(
                    clipBehavior: Clip.none,
                    children: [
                      HeaderActionButton(
                        icon: Icons.notifications_none_rounded,
                        tooltip: 'Notifications',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ActivityScreen(),
                          ),
                        ),
                      ),
                      if (unread > 0) const _UnreadDot(),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Expanded(
              child: FeedList(
                scope: const FeedScope.home(),
                emptyText: 'No posts yet. Be the first to post!',
                header: Column(
                  children: [
                    ComposerPrompt(
                      username: services.repository.username,
                      avatarUrl: services.repository.avatarUrl,
                      onTap: onOpenComposer,
                    ),
                    const SizedBox(height: 12),
                    const SyncBanner(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Messages icon with the number of unread messages (muted people excluded).
class _MessagesButton extends StatefulWidget {
  const _MessagesButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_MessagesButton> createState() => _MessagesButtonState();
}

class _MessagesButtonState extends State<_MessagesButton> {
  Stream<List<ChatMessage>>? _unread;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _unread ??= RepositoryScope.servicesOf(context).chat.watchUnread();
  }

  @override
  Widget build(BuildContext context) {
    final muted = RepositoryScope.servicesOf(context).notifications.muted;
    return StreamBuilder<List<ChatMessage>>(
      stream: _unread,
      builder: (context, snapshot) => ValueListenableBuilder<Set<String>>(
        valueListenable: muted,
        builder: (context, mutedIds, _) {
          final count = (snapshot.data ?? const <ChatMessage>[])
              .where((m) => !mutedIds.contains(m.senderId))
              .length;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              HeaderActionButton(
                icon: Icons.message_rounded,
                tooltip: 'Messages',
                onTap: widget.onTap,
              ),
              if (count > 0) _CountBadge(count: count),
            ],
          );
        },
      ),
    );
  }
}

/// Small red dot on the corner of a header button: something new to see.
class _UnreadDot extends StatelessWidget {
  const _UnreadDot();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: -2,
      top: -2,
      child: Semantics(
        label: 'New notifications',
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: kRed,
            shape: BoxShape.circle,
            // Ring in the page color so the dot stands off the button.
            border: Border.all(color: kCream, width: 2),
          ),
        ),
      ),
    );
  }
}

/// Small red counter on the corner of a header button.
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: -6,
      top: -6,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        constraints: const BoxConstraints(minWidth: 18),
        decoration: BoxDecoration(
          color: kRed,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: kCardWhite, width: 1.5),
        ),
        child: Text(
          count > 99 ? '99+' : '$count',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: kWhite,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// "What's on your mind?" box that opens the composer.
class ComposerPrompt extends StatelessWidget {
  const ComposerPrompt({
    super.key,
    required this.username,
    this.avatarUrl,
    required this.onTap,
    this.hint = 'What’s on your mind?',
  });

  final String username;
  final String? avatarUrl;
  final VoidCallback onTap;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: kCardWhite,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            UserAvatar(name: username, url: avatarUrl, radius: 23),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                hint,
                style: TextStyle(fontSize: 14, color: kSecondaryText),
              ),
            ),
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: kGreen,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.add_rounded, color: kWhite),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tells the user when changes are waiting to sync or the cloud is offline.
class SyncBanner extends StatelessWidget {
  const SyncBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = RepositoryScope.of(context);
    return StreamBuilder<SyncState>(
      stream: repository.watchSyncState(),
      builder: (context, snapshot) {
        final state = snapshot.data ?? const SyncState();
        if (!state.isOffline && state.pendingChanges == 0) {
          return const SizedBox.shrink();
        }

        final String message;
        if (state.isOffline) {
          message = state.pendingChanges > 0
              ? 'Offline · ${state.pendingChanges} change(s) saved on this '
                    'device and will sync later'
              : 'Offline · showing saved posts';
        } else {
          message = 'Syncing ${state.pendingChanges} change(s)…';
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: state.isOffline ? const Color(0xFFFFF4E5) : kPaleGreen,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(
                state.isOffline ? Icons.cloud_off_rounded : Icons.cloud_upload,
                size: 18,
                color: state.isOffline ? const Color(0xFFB26A00) : kGreen,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(fontSize: 12, color: kMainText),
                ),
              ),
              if (state.isOffline)
                TextButton(
                  onPressed: state.isSyncing
                      ? null
                      : () => repository.refresh().catchError((Object e) {
                          if (context.mounted) showErrorSnackBar(context, e);
                        }),
                  child: const Text('Retry'),
                ),
            ],
          ),
        );
      },
    );
  }
}

class HeaderActionButton extends StatelessWidget {
  const HeaderActionButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: kCardWhite,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 20, color: kMainText),
        ),
      ),
    );
  }
}
