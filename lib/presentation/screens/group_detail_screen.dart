import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/models.dart';
import '../../data/repository_scope.dart';
import '../widgets/common_widgets.dart';
import '../widgets/feed_list.dart';
import 'composer_screen.dart';
import 'follow_list_screen.dart';
import 'group_reports_screen.dart';
import 'groups_screen.dart';
import 'home_screen.dart';

/// A group or page with its own timeline.
class GroupDetailScreen extends StatefulWidget {
  const GroupDetailScreen({super.key, required this.groupId});

  final String groupId;

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen> {
  Future<Group>? _future;
  bool _busy = false;

  AppServices get _services => RepositoryScope.servicesOf(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _services.groups.getGroup(widget.groupId);
  }

  void _reload() => setState(() {
    _future = _services.groups.getGroup(widget.groupId);
  });

  Future<void> _run(Future<void> Function() action, {String? done}) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      if (done != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(done)));
      }
      _reload();
    } catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave(Group group) async {
    final confirmed = await _confirm(
      'Leave ${group.name}?',
      'You can join again later.',
      'Leave',
    );
    if (confirmed) {
      await _run(() => _services.groups.leave(group), done: 'You left.');
    }
  }

  Future<void> _delete(Group group) async {
    final confirmed = await _confirm(
      'Delete ${group.name}?',
      'All posts in this ${group.kind.label.toLowerCase()} will be deleted '
          'for everyone. This cannot be undone.',
      'Delete',
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      await _services.groups.deleteGroup(group.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${group.name} was deleted.')));
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() => _busy = false);
        showErrorSnackBar(context, error);
      }
    }
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: kRed),
            child: Text(action),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _compose(Group group) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ComposerScreen(
          groupId: group.id,
          groupName: group.name,
          onBack: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  void _showMembers(Group group) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kCream,
      builder: (_) => RepositoryScope(
        services: _services,
        child: _MembersSheet(group: group, onChanged: _reload),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCream,
      appBar: AppBar(
        backgroundColor: kCream,
        title: FutureBuilder<Group>(
          future: _future,
          builder: (context, snapshot) => Text(snapshot.data?.name ?? ''),
        ),
      ),
      body: FutureBuilder<Group>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorRetry(
              message: errorMessage(snapshot.error!),
              onRetry: _reload,
            );
          }
          final group = snapshot.data;
          if (group == null) {
            return const Center(
              child: CircularProgressIndicator(color: kGreen),
            );
          }
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: FeedList(
              scope: FeedScope.group(group.id),
              isGroupAdmin: group.isAdmin,
              emptyText: group.canPost
                  ? 'No posts yet. Start the conversation!'
                  : 'No posts yet.',
              header: _buildHeader(group),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(Group group) {
    final isPage = group.kind == GroupKind.page;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: kCardWhite,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (group.coverUrl != null)
                AspectRatio(
                  aspectRatio: 3,
                  child: Image.network(
                    group.coverUrl!,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    errorBuilder: (_, _, _) =>
                        Container(color: const Color(0xFFEDEFF3)),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: _headerBody(group, isPage),
              ),
            ],
          ),
        ),
        ..._afterHeader(group, isPage),
      ],
    );
  }

  Widget _headerBody(Group group, bool isPage) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            GroupIcon(group: group, size: 56),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  InkWell(
                    onTap: () => _showMembers(group),
                    child: Text(
                      '${group.kind.label} · ${group.memberCount} '
                      '${isPage ? 'followers' : 'members'}',
                      style: const TextStyle(
                        color: kGreen,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (group.description != null) ...[
          const SizedBox(height: 10),
          Text(group.description!),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (!group.isMember)
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run(
                        () => _services.groups.join(group.id),
                        done: isPage
                            ? 'You now follow ${group.name}.'
                            : 'Welcome to ${group.name}!',
                      ),
                style: FilledButton.styleFrom(backgroundColor: kGreen),
                icon: const Icon(Icons.group_add_rounded),
                label: Text(isPage ? 'Follow page' : 'Join group'),
              )
            else if (group.myRole != GroupRole.owner)
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _leave(group),
                icon: const Icon(Icons.logout_rounded),
                label: Text(isPage ? 'Unfollow' : 'Leave'),
              ),
            if (group.isMember)
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run(
                        () => _services.groups.setNotifications(
                          group.id,
                          !group.notificationsOn,
                        ),
                        done: group.notificationsOn
                            ? 'Notifications from ${group.name} are off.'
                            : 'You will be notified about new posts in '
                                  '${group.name}.',
                      ),
                style: group.notificationsOn
                    ? OutlinedButton.styleFrom(
                        foregroundColor: kGreen,
                        backgroundColor: kPaleGreen,
                      )
                    : null,
                icon: Icon(
                  group.notificationsOn
                      ? Icons.notifications_active_rounded
                      : Icons.notifications_off_outlined,
                ),
                label: Text(
                  group.notificationsOn ? 'Notifications on' : 'Notify me',
                ),
              ),
            if (group.isAdmin)
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        final updated = await showGroupForm(
                          context,
                          group: group,
                        );
                        if (updated != null) _reload();
                      },
                icon: const Icon(Icons.edit_rounded),
                label: const Text('Edit'),
              ),
            if (group.isAdmin) _ReportsButton(group: group, onChanged: _reload),
            if (group.myRole == GroupRole.owner)
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _delete(group),
                style: OutlinedButton.styleFrom(foregroundColor: kRed),
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Delete'),
              ),
          ],
        ),
      ],
    );
  }

  List<Widget> _afterHeader(Group group, bool isPage) {
    return [
      const SizedBox(height: 12),
      if (group.canPost) ...[
        ComposerPrompt(
          username: _services.repository.username,
          avatarUrl: _services.repository.avatarUrl,
          hint: 'Write something in ${group.name}…',
          onTap: () => _compose(group),
        ),
        const SizedBox(height: 12),
      ] else if (isPage && group.isMember)
        Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text(
            'Only page admins can post here.',
            style: TextStyle(color: kSecondaryText),
          ),
        ),
      const SyncBanner(),
    ];
  }
}

/// "Reports (n)" for group owners/staff; opens the review screen.
class _ReportsButton extends StatefulWidget {
  const _ReportsButton({required this.group, required this.onChanged});

  final Group group;
  final VoidCallback onChanged;

  @override
  State<_ReportsButton> createState() => _ReportsButtonState();
}

class _ReportsButtonState extends State<_ReportsButton> {
  Future<int>? _count;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _count ??= _load();
  }

  Future<int> _load() =>
      RepositoryScope.servicesOf(context).groups
          .pendingReportCount(widget.group.id);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: _count,
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        return OutlinedButton.icon(
          onPressed: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => GroupReportsScreen(group: widget.group),
              ),
            );
            if (!mounted) return;
            setState(() {
              _count = _load();
            });
            widget.onChanged();
          },
          style: count > 0
              ? OutlinedButton.styleFrom(foregroundColor: kRed)
              : null,
          icon: const Icon(Icons.flag_outlined),
          label: Text(count > 0 ? 'Reports ($count)' : 'Reports'),
        );
      },
    );
  }
}

class _MembersSheet extends StatefulWidget {
  const _MembersSheet({required this.group, required this.onChanged});

  final Group group;
  final VoidCallback onChanged;

  @override
  State<_MembersSheet> createState() => _MembersSheetState();
}

class _MembersSheetState extends State<_MembersSheet> {
  Future<List<GroupMember>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  Future<List<GroupMember>> _load() =>
      RepositoryScope.servicesOf(context).groups.members(widget.group.id);

  Future<void> _setRole(GroupMember member, GroupRole role) async {
    try {
      await RepositoryScope.servicesOf(context).groups
          .setRole(widget.group.id, member.profile.id, role);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            role == GroupRole.admin
                ? '${member.profile.name} is now staff.'
                : '${member.profile.name} is no longer staff.',
          ),
        ),
      );
      setState(() {
        _future = _load();
      });
    } catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    }
  }

  Future<void> _remove(GroupMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Kick ${member.profile.name}?'),
        content: const Text('They can join again later.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: kRed),
            child: const Text('Kick'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await RepositoryScope.servicesOf(context).groups
          .removeMember(widget.group.id, member.profile.id);
      widget.onChanged();
      if (!mounted) return;
      setState(() {
        _future = _load();
      });
    } catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.7,
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Members',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<GroupMember>>(
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
                final members = snapshot.data!;
                return ListView.builder(
                  itemCount: members.length,
                  itemBuilder: (context, index) {
                    final member = members[index];
                    final group = widget.group;
                    // Owner manages everyone; staff can kick regular members.
                    final canManage =
                        member.role != GroupRole.owner &&
                        (group.isOwner ||
                            (group.isAdmin && member.role == GroupRole.member));
                    final roleChip = member.role == GroupRole.member
                        ? null
                        : Chip(
                            label: Text(member.role.label),
                            visualDensity: VisualDensity.compact,
                          );
                    return ProfileTile(
                      profile: member.profile,
                      trailing: !canManage
                          ? roleChip
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ?roleChip,
                                PopupMenuButton<String>(
                                  tooltip: 'Manage member',
                                  onSelected: (action) => switch (action) {
                                    'staff' => _setRole(
                                      member,
                                      GroupRole.admin,
                                    ),
                                    'member' => _setRole(
                                      member,
                                      GroupRole.member,
                                    ),
                                    _ => _remove(member),
                                  },
                                  itemBuilder: (_) => [
                                    if (group.isOwner &&
                                        member.role == GroupRole.member)
                                      const PopupMenuItem(
                                        value: 'staff',
                                        child: Text('Make staff'),
                                      ),
                                    if (group.isOwner &&
                                        member.role == GroupRole.admin)
                                      const PopupMenuItem(
                                        value: 'member',
                                        child: Text('Remove from staff'),
                                      ),
                                    const PopupMenuItem(
                                      value: 'kick',
                                      child: Text(
                                        'Kick from group',
                                        style: TextStyle(color: kRed),
                                      ),
                                    ),
                                  ],
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
