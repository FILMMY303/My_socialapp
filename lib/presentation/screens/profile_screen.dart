import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/models.dart';
import '../../data/repository_scope.dart';
import '../navigation.dart';
import '../widgets/common_widgets.dart';
import '../widgets/feed_list.dart';
import '../widgets/media_view.dart';
import 'follow_list_screen.dart';
import 'settings_screen.dart';

/// Public/private profile with follow, message and the user's posts.
/// Shows the signed-in user's own profile when [userId] is null.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.userId});

  final String? userId;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileData {
  const _ProfileData(this.profile, this.stats, this.follow);

  final Profile profile;
  final ProfileStats stats;
  final FollowStatus follow;
}

class _ProfileScreenState extends State<ProfileScreen> {
  Future<_ProfileData>? _future;
  bool _followBusy = false;
  bool _showSaved = false;

  AppServices get _services => RepositoryScope.servicesOf(context);
  String get _id => widget.userId ?? _services.userId;
  bool get _isMe => _id == _services.userId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  Future<_ProfileData> _load() async {
    final profiles = _services.profiles;
    final results = await Future.wait([
      profiles.getProfile(_id),
      profiles.getStats(_id),
      profiles.followStatus(_id),
    ]);
    return _ProfileData(
      results[0] as Profile,
      results[1] as ProfileStats,
      results[2] as FollowStatus,
    );
  }

  void _reload() => setState(() {
    _future = _load();
  });

  Future<void> _toggleFollow(_ProfileData data) async {
    final profiles = _services.profiles;
    if (data.follow != FollowStatus.none) {
      final label = data.follow == FollowStatus.pending
          ? 'Cancel follow request?'
          : 'Unfollow ${data.profile.name}?';
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(label),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('No'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Yes'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() => _followBusy = true);
    try {
      if (data.follow == FollowStatus.none) {
        final status = await profiles.follow(_id);
        if (mounted && status == FollowStatus.pending) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Follow request sent.')));
        }
      } else {
        await profiles.unfollow(_id);
      }
      if (mounted) _reload();
    } catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  Future<void> _toggleBlock(bool isBlocked) async {
    final services = _services;
    if (!isBlocked) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Block this person?'),
          content: const Text(
            "You won't see each other's posts or comments, and you can't "
            'message or follow each other. They are not told you blocked them.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: kRed),
              child: const Text('Block'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    try {
      if (isBlocked) {
        await services.blocks.unblock(_id);
      } else {
        await services.blocks.block(_id);
        await services.repository.removeUserContent(_id);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isBlocked ? 'Unblocked.' : 'Blocked.')),
      );
      _reload();
    } catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    }
  }

  Future<void> _signOut() async {
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    }
  }

  void _openList(FollowListKind kind) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => FollowListScreen(userId: _id, kind: kind),
          ),
        )
        .then((_) {
          if (mounted) _reload();
        });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCream,
      appBar: AppBar(
        backgroundColor: kCream,
        elevation: 0,
        title: Text(
          'Profile',
          style: TextStyle(color: kMainText, fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
        actions: [
          if (_isMe)
            IconButton(
              tooltip: 'Settings',
              // Profile edits happen in settings; show them on return.
              onPressed: () => Navigator.of(context)
                  .push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  )
                  .then((_) {
                    if (mounted) _reload();
                  }),
              icon: Icon(Icons.settings_outlined, color: kMainText),
            ),
          if (_isMe)
            IconButton(
              tooltip: 'Sign out',
              onPressed: _signOut,
              icon: Icon(Icons.logout_rounded, color: kMainText),
            )
          else
            ValueListenableBuilder<Set<String>>(
              valueListenable: _services.blocks.blocked,
              builder: (context, blocked, _) => PopupMenuButton<String>(
                tooltip: 'More',
                onSelected: (_) => _toggleBlock(blocked.contains(_id)),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'block',
                    child: Text(
                      blocked.contains(_id) ? 'Unblock' : 'Block',
                      style: blocked.contains(_id)
                          ? null
                          : const TextStyle(color: kRed),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      body: FutureBuilder<_ProfileData>(
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
          final data = snapshot.data!;
          final header = _buildHeader(data);
          if (_services.blocks.isBlocked(_id)) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: ListView(
                children: [
                  header,
                  const SizedBox(height: 40),
                  Icon(Icons.block_rounded, size: 40, color: kMuted),
                  const SizedBox(height: 8),
                  Text(
                    'You blocked ${data.profile.name}.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    "You won't see each other's posts or comments, and you "
                    "can't message or follow each other.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: kSecondaryText),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: OutlinedButton(
                      onPressed: () => _toggleBlock(true),
                      child: const Text('Unblock'),
                    ),
                  ),
                ],
              ),
            );
          }
          final canSeePosts =
              _isMe ||
              !data.profile.isPrivate ||
              data.follow == FollowStatus.accepted;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: canSeePosts && _showSaved
                ? _SavedPosts(
                    ownerId: _id,
                    isMe: _isMe,
                    isPublic: data.profile.savedPublic,
                    header: header,
                  )
                : canSeePosts
                ? FeedList(
                    scope: FeedScope.user(_id),
                    header: header,
                    emptyText: _isMe
                        ? "You haven't posted yet."
                        : 'No posts yet.',
                  )
                : ListView(
                    children: [
                      header,
                      const SizedBox(height: 40),
                      Icon(Icons.lock_outline_rounded, size: 40, color: kMuted),
                      const SizedBox(height: 8),
                      Text(
                        'This account is private',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: kMainText,
                        ),
                      ),
                      Text(
                        'Follow this account to see their posts.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: kSecondaryText),
                      ),
                    ],
                  ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(_ProfileData data) {
    final profile = data.profile;
    final stats = data.stats;

    return Column(
      children: [
        const SizedBox(height: 8),
        UserAvatar(name: profile.name, url: profile.avatarUrl, radius: 48),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                profile.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 20,
                  color: kMainText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (profile.isPrivate) ...[
              const SizedBox(width: 6),
              const Tooltip(
                message: 'Private account',
                child: Icon(Icons.lock_outline_rounded, size: 18),
              ),
            ],
          ],
        ),
        Text(
          '@${profile.username}',
          style: TextStyle(fontSize: 13, color: kSecondaryText),
        ),
        if (profile.bio != null) ...[
          const SizedBox(height: 8),
          Text(
            profile.bio!,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: kMainText),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _Stat(label: 'Posts', value: stats.posts),
            _Stat(
              label: 'Followers',
              value: stats.followers,
              onTap: () => _openList(FollowListKind.followers),
            ),
            _Stat(
              label: 'Following',
              value: stats.following,
              onTap: () => _openList(FollowListKind.following),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_isMe) ...[
          if (stats.requests > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _openList(FollowListKind.requests),
                icon: const Icon(Icons.person_add_alt_rounded, size: 18),
                label: Text('${stats.requests} requests'),
              ),
            ),
        ] else if (!_services.blocks.isBlocked(_id))
          Row(
            children: [
              Expanded(
                child: _PrimaryButton(
                  label: switch (data.follow) {
                    FollowStatus.none =>
                      profile.isPrivate ? 'Request to follow' : 'Follow',
                    FollowStatus.pending => 'Requested',
                    FollowStatus.accepted => 'Following',
                  },
                  outlined: data.follow != FollowStatus.none,
                  busy: _followBusy,
                  onPressed: () => _toggleFollow(data),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _PrimaryButton(
                  label: 'Message',
                  outlined: true,
                  onPressed: () => openChat(context, profile),
                ),
              ),
            ],
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            _TabLabel(
              label: 'Posts',
              selected: !_showSaved,
              onTap: () => setState(() => _showSaved = false),
            ),
            _TabLabel(
              label: 'Saved',
              icon: !_isMe && !profile.savedPublic
                  ? Icons.lock_outline_rounded
                  : null,
              selected: _showSaved,
              onTap: () => setState(() => _showSaved = true),
            ),
          ],
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.onTap});

  final String label;
  final int value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          children: [
            Text(
              '$value',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: kMainText,
              ),
            ),
            Text(label, style: TextStyle(fontSize: 12, color: kSecondaryText)),
          ],
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.onPressed,
    this.outlined = false,
    this.busy = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool outlined;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final child = busy
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: kGreen),
          )
        : Text(
            label,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    );
    const padding = EdgeInsets.symmetric(vertical: 14);
    return outlined
        ? OutlinedButton(
            onPressed: busy ? null : onPressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: kGreen,
              side: const BorderSide(color: kGreen),
              shape: shape,
              padding: padding,
            ),
            child: child,
          )
        : ElevatedButton(
            onPressed: busy ? null : onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: kGreen,
              foregroundColor: kWhite,
              elevation: 0,
              shape: shape,
              padding: padding,
            ),
            child: child,
          );
  }
}

class _TabLabel extends StatelessWidget {
  const _TabLabel({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final color = selected ? kGreen : kSecondaryText;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                if (icon != null) ...[
                  const SizedBox(width: 4),
                  Icon(icon, size: 14, color: color),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Container(height: 2, color: selected ? kGreen : Colors.transparent),
          ],
        ),
      ),
    );
  }
}

/// The posts [ownerId] saved. Others see them only when the owner allows it.
class _SavedPosts extends StatefulWidget {
  const _SavedPosts({
    required this.ownerId,
    required this.isMe,
    required this.isPublic,
    required this.header,
  });

  final String ownerId;
  final bool isMe;
  final bool isPublic;
  final Widget header;

  @override
  State<_SavedPosts> createState() => _SavedPostsState();
}

class _SavedPostsState extends State<_SavedPosts> {
  Future<List<String>>? _ids;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ids ??= _load();
  }

  Future<List<String>> _load() =>
      RepositoryScope.servicesOf(context).saved.savedPostIds(widget.ownerId);

  Widget _message(String text, {IconData? icon}) => ListView(
    children: [
      widget.header,
      const SizedBox(height: 40),
      if (icon != null) Icon(icon, size: 36, color: kMuted),
      const SizedBox(height: 8),
      Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: kSecondaryText),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (!widget.isMe && !widget.isPublic) {
      return _message(
        'Saved posts are private.',
        icon: Icons.lock_outline_rounded,
      );
    }
    final mySaved = RepositoryScope.servicesOf(context).saved.mySaved;
    return FutureBuilder<List<String>>(
      future: _ids,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ListView(
            children: [
              widget.header,
              ErrorRetry(
                message: errorMessage(snapshot.error!),
                onRetry: () => setState(() {
                  _ids = _load();
                }),
              ),
            ],
          );
        }
        if (!snapshot.hasData) {
          return ListView(
            children: [
              widget.header,
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator(color: kGreen)),
              ),
            ],
          );
        }
        // On your own profile, unsaving removes the post right away.
        return ValueListenableBuilder<Set<String>>(
          valueListenable: mySaved,
          builder: (context, mine, _) {
            final ids = widget.isMe
                ? snapshot.data!.where(mine.contains).toList()
                : snapshot.data!;
            if (ids.isEmpty) {
              return _message(
                widget.isMe
                    ? 'Save posts from the ... menu to find them here.'
                    : 'No saved posts.',
                icon: Icons.bookmark_border_rounded,
              );
            }
            return FeedList(
              key: ValueKey(ids.join()),
              scope: FeedScope.ids(ids),
              header: widget.header,
            );
          },
        );
      },
    );
  }
}
