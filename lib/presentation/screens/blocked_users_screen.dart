import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/models.dart';
import '../../data/repository_scope.dart';
import '../widgets/common_widgets.dart';
import 'follow_list_screen.dart';

/// People the signed-in user blocked, with Unblock.
class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  Future<List<Profile>>? _future;
  final _busy = <String>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= RepositoryScope.servicesOf(context).blocks.blockedProfiles();
  }

  Future<void> _unblock(Profile profile) async {
    final services = RepositoryScope.servicesOf(context);
    setState(() => _busy.add(profile.id));
    try {
      await services.blocks.unblock(profile.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${profile.name} is unblocked.')));
      setState(() {
        _future = services.blocks.blockedProfiles();
      });
    } catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    } finally {
      if (mounted) setState(() => _busy.remove(profile.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCream,
      appBar: AppBar(
        backgroundColor: kCream,
        title: const Text('Blocked users'),
      ),
      body: FutureBuilder<List<Profile>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorRetry(
              message: errorMessage(snapshot.error!),
              onRetry: () => setState(() {
                _future = RepositoryScope.servicesOf(context).blocks
                    .blockedProfiles();
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
                "You haven't blocked anyone.",
                style: TextStyle(color: kSecondaryText),
              ),
            );
          }
          return ListView(
            children: [
              for (final person in people)
                ProfileTile(
                  profile: person,
                  trailing: _busy.contains(person.id)
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : OutlinedButton(
                          onPressed: () => _unblock(person),
                          child: const Text('Unblock'),
                        ),
                ),
            ],
          );
        },
      ),
    );
  }
}
