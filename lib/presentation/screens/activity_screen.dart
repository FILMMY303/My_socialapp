import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/time_ago.dart';
import '../../data/models/models.dart';
import '../../data/repository_scope.dart';
import '../navigation.dart';
import '../widgets/common_widgets.dart';
import '../widgets/media_view.dart';

/// Notifications: new followers, follow requests (accept/decline here),
/// and new posts from people and pages you follow.
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  Future<List<ActivityNotification>>? _future;
  final _busy = <String>{};

  AppServices get _services => RepositoryScope.servicesOf(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  Future<List<ActivityNotification>> _load() async {
    final items = await _services.activity.list();
    // Opening the page counts as reading everything on it.
    _services.activity.markAllRead().catchError((_) {});
    return items;
  }

  Future<void> _reload() async {
    final future = _load();
    setState(() {
      _future = future;
    });
    await future.catchError((_) => <ActivityNotification>[]);
  }

  Future<void> _answerRequest(ActivityNotification n, bool accept) async {
    setState(() => _busy.add(n.id));
    try {
      if (accept) {
        await _services.profiles.acceptRequest(n.actor.id);
      } else {
        await _services.profiles.removeFollower(n.actor.id);
      }
      if (mounted) await _reload();
    } catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    } finally {
      if (mounted) setState(() => _busy.remove(n.id));
    }
  }

  Future<void> _delete(ActivityNotification n) async {
    try {
      await _services.activity.delete(n);
    } catch (error) {
      if (mounted) {
        showErrorSnackBar(context, error);
        await _reload();
      }
    }
  }

  void _open(ActivityNotification n) {
    if (n.isAboutPost) {
      openPost(context, n.postId!);
    } else {
      openProfile(context, n.actor.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCream,
      appBar: AppBar(
        backgroundColor: kCream,
        title: const Text('Notifications'),
      ),
      body: FutureBuilder<List<ActivityNotification>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorRetry(
              message: errorMessage(snapshot.error!),
              onRetry: _reload,
            );
          }
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: kGreen),
            );
          }
          final items = snapshot.data!;
          return RefreshIndicator(
            color: kGreen,
            onRefresh: _reload,
            child: items.isEmpty
                ? ListView(
                    children: [
                      SizedBox(height: 120),
                      Icon(
                        Icons.notifications_none_rounded,
                        size: 40,
                        color: kMuted,
                      ),
                      SizedBox(height: 8),
                      Center(
                        child: Text(
                          'No notifications yet.',
                          style: TextStyle(color: kSecondaryText),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final n = items[index];
                      return Dismissible(
                        key: ValueKey(n.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: kRed,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          child: const Icon(
                            Icons.delete_outline_rounded,
                            color: kWhite,
                          ),
                        ),
                        onDismissed: (_) {
                          items.removeAt(index);
                          _delete(n);
                        },
                        child: _ActivityTile(
                          notification: n,
                          busy: _busy.contains(n.id),
                          onTap: () => _open(n),
                          onAccept: () => _answerRequest(n, true),
                          onDecline: () => _answerRequest(n, false),
                        ),
                      );
                    },
                  ),
          );
        },
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({
    required this.notification,
    required this.busy,
    required this.onTap,
    required this.onAccept,
    required this.onDecline,
  });

  final ActivityNotification notification;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  IconData get _icon => switch (notification.type) {
    ActivityType.follow ||
    ActivityType.followAccepted => Icons.person_add_alt_1_rounded,
    ActivityType.followRequest => Icons.person_outline_rounded,
    ActivityType.friendPost => Icons.article_rounded,
    ActivityType.pagePost => Icons.flag_rounded,
    ActivityType.groupPost => Icons.groups_rounded,
    ActivityType.comment || ActivityType.reply => Icons.mode_comment_rounded,
    ActivityType.reaction => Icons.favorite_rounded,
    ActivityType.share => Icons.share_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final n = notification;
    return Material(
      color: n.isRead ? Colors.transparent : kPaleGreen,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  GestureDetector(
                    onTap: () => n.isFromPage && n.groupId != null
                        ? openGroup(context, n.groupId!)
                        : openProfile(context, n.actor.id),
                    child: n.isFromPage
                        ? PageAvatar(
                            name: n.displayName,
                            url: n.displayAvatarUrl,
                          )
                        : UserAvatar(
                            name: n.displayName,
                            url: n.displayAvatarUrl,
                          ),
                  ),
                  Positioned(
                    right: -4,
                    bottom: -4,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: kGreen,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(_icon, size: 12, color: kWhite),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(n.text, style: TextStyle(color: kMainText)),
                    const SizedBox(height: 2),
                    Text(
                      timeAgo(n.createdAt),
                      style: TextStyle(fontSize: 11, color: kMuted),
                    ),
                    if (n.type == ActivityType.followRequest) ...[
                      const SizedBox(height: 6),
                      busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Row(
                              children: [
                                FilledButton(
                                  onPressed: onAccept,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: kGreen,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  child: const Text('Accept'),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton(
                                  onPressed: onDecline,
                                  style: OutlinedButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  child: const Text('Decline'),
                                ),
                              ],
                            ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
