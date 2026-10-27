import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/models.dart';
import '../../data/repository_scope.dart';
import '../widgets/common_widgets.dart';
import '../widgets/media_view.dart';

/// One switch per joined group/page for new-post notifications.
class GroupNotificationsScreen extends StatefulWidget {
  const GroupNotificationsScreen({super.key});

  @override
  State<GroupNotificationsScreen> createState() =>
      _GroupNotificationsScreenState();
}

class _GroupNotificationsScreenState extends State<GroupNotificationsScreen> {
  Future<List<Group>>? _future;

  /// Switch values changed on this screen, shown before the reload finishes.
  final _overrides = <String, bool>{};
  final _saving = <String>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  Future<List<Group>> _load() async {
    final groups = await RepositoryScope.servicesOf(context).groups
        .listGroups();
    return [
      for (final g in groups)
        if (g.isMember) g,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  Future<void> _set(Group group, bool enabled) async {
    setState(() {
      _overrides[group.id] = enabled;
      _saving.add(group.id);
    });
    try {
      await RepositoryScope.servicesOf(context).groups
          .setNotifications(group.id, enabled);
    } catch (error) {
      if (!mounted) return;
      setState(() => _overrides.remove(group.id));
      showErrorSnackBar(context, error);
    } finally {
      if (mounted) setState(() => _saving.remove(group.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCream,
      appBar: AppBar(
        backgroundColor: kCream,
        title: const Text('Groups & pages'),
      ),
      body: FutureBuilder<List<Group>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorRetry(
              message: errorMessage(snapshot.error!),
              onRetry: () => setState(() => _future = _load()),
            );
          }
          final groups = snapshot.data;
          if (groups == null) {
            return const Center(
              child: CircularProgressIndicator(color: kGreen),
            );
          }
          if (groups.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Join a group or follow a page to choose its '
                  'notifications here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: kSecondaryText),
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 0, 6, 12),
                child: Text(
                  'Get a notification when someone posts. Pages start on, '
                  'groups start off.',
                  style: TextStyle(color: kSecondaryText, fontSize: 12),
                ),
              ),
              Material(
                color: kCardWhite,
                borderRadius: BorderRadius.circular(20),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (final group in groups)
                      SwitchListTile(
                        value: _overrides[group.id] ?? group.notificationsOn,
                        activeThumbColor: kGreen,
                        onChanged: _saving.contains(group.id)
                            ? null
                            : (on) => _set(group, on),
                        secondary: group.kind == GroupKind.page
                            ? PageAvatar(name: group.name, url: group.avatarUrl)
                            : UserAvatar(
                                name: group.name,
                                url: group.avatarUrl,
                              ),
                        title: Text(
                          group.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: kMainText,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          group.kind.label,
                          style: TextStyle(color: kSecondaryText, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
