import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/models.dart';
import '../../data/repository_scope.dart';
import '../navigation.dart';
import '../widgets/common_widgets.dart';
import '../widgets/media_view.dart';

enum FollowListKind {
  followers('Followers'),
  following('Following'),
  requests('Follow requests');

  const FollowListKind(this.title);

  final String title;
}

class FollowListScreen extends StatefulWidget {
  const FollowListScreen({super.key, required this.userId, required this.kind});

  final String userId;
  final FollowListKind kind;

  @override
  State<FollowListScreen> createState() => _FollowListScreenState();
}

class _FollowListScreenState extends State<FollowListScreen> {
  Future<List<Profile>>? _future;
  final _busy = <String>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  Future<List<Profile>> _load() {
    final profiles = RepositoryScope.servicesOf(context).profiles;
    return switch (widget.kind) {
      FollowListKind.followers => profiles.followers(widget.userId),
      FollowListKind.following => profiles.following(widget.userId),
      FollowListKind.requests => profiles.followers(
        widget.userId,
        pending: true,
      ),
    };
  }

  Future<void> _act(Profile profile, Future<void> Function() action) async {
    setState(() => _busy.add(profile.id));
    try {
      await action();
      if (!mounted) return;
      setState(() {
        _future = _load();
      });
    } catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    } finally {
      if (mounted) setState(() => _busy.remove(profile.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = RepositoryScope.servicesOf(context);
    final isMine = widget.userId == services.userId;

    return Scaffold(
      backgroundColor: kCream,
      appBar: AppBar(backgroundColor: kCream, title: Text(widget.kind.title)),
      body: FutureBuilder<List<Profile>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorRetry(
              message: errorMessage(snapshot.error!),
              onRetry: () => setState(() {
                _future = _load();
              }),
            );
          }
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: kGreen),
            );
          }
          final people = snapshot.data!;
          if (people.isEmpty) {
            return Center(
              child: Text(
                widget.kind == FollowListKind.requests
                    ? 'No follow requests.'
                    : 'Nobody here yet.',
                style: TextStyle(color: kSecondaryText),
              ),
            );
          }
          return RefreshIndicator(
            color: kGreen,
            onRefresh: () async {
              final future = _load();
              setState(() {
                _future = future;
              });
              await future.catchError((_) => <Profile>[]);
            },
            child: ListView.builder(
              itemCount: people.length,
              itemBuilder: (context, index) {
                final person = people[index];
                final busy = _busy.contains(person.id);
                return ProfileTile(
                  profile: person,
                  trailing: !isMine || widget.kind == FollowListKind.following
                      ? null
                      : busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : widget.kind == FollowListKind.requests
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: () => _act(
                                person,
                                () =>
                                    services.profiles.acceptRequest(person.id),
                              ),
                              child: const Text('Accept'),
                            ),
                            TextButton(
                              onPressed: () => _act(
                                person,
                                () =>
                                    services.profiles.removeFollower(person.id),
                              ),
                              style: TextButton.styleFrom(
                                foregroundColor: kRed,
                              ),
                              child: const Text('Decline'),
                            ),
                          ],
                        )
                      : TextButton(
                          onPressed: () => _act(
                            person,
                            () => services.profiles.removeFollower(person.id),
                          ),
                          child: const Text('Remove'),
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

/// A person in a list; tapping opens their profile.
class ProfileTile extends StatelessWidget {
  const ProfileTile({
    super.key,
    required this.profile,
    this.trailing,
    this.onTap,
  });

  final Profile profile;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap ?? () => openProfile(context, profile.id),
      leading: UserAvatar(name: profile.name, url: profile.avatarUrl),
      title: Row(
        children: [
          Flexible(
            child: Text(
              profile.name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          if (profile.isPrivate) ...[
            const SizedBox(width: 4),
            Icon(Icons.lock_outline_rounded, size: 14, color: kMuted),
          ],
        ],
      ),
      subtitle: Text('@${profile.username}'),
      trailing: trailing,
    );
  }
}
