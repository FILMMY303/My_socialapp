import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../data/repositories/social_repository.dart';
import '../../data/repository_scope.dart';
import '../../data/models/models.dart';
import '../../data/services/notification_service.dart';
import '../navigation.dart';
import '../widgets/common_widgets.dart';
import '../widgets/media_view.dart';
import 'activity_screen.dart';
import 'composer_screen.dart';
import 'direct_messages_screen.dart';
import 'search_screen.dart';
import 'groups_screen.dart';
import 'home_screen.dart';
import 'profile_screen.dart';

class MySocialHome extends StatefulWidget {
  const MySocialHome({super.key});

  @override
  State<MySocialHome> createState() => _MySocialHomeState();
}

class _MySocialHomeState extends State<MySocialHome> {
  int _selectedIndex = 0;
  SocialRepository? _repository;
  StreamSubscription<String>? _syncErrors;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repository = RepositoryScope.of(context);
    if (repository != _repository) {
      _repository = repository;
      _syncErrors?.cancel();
      // Errors from background sync have no button to report back to.
      _syncErrors = repository.errors.listen((message) {
        if (mounted) showErrorSnackBar(context, AppException(message));
      });
      _dmAlerts?.cancel();
      _dmAlerts = RepositoryScope.servicesOf(context).notifications.events
          .listen(_showDmBanner);
      _activityAlerts?.cancel();
      _activityAlerts = RepositoryScope.servicesOf(context).activity.events
          .listen(_showActivityBanner);
    }
  }

  StreamSubscription<ActivityNotification>? _activityAlerts;

  void _showActivityBanner(ActivityNotification n) {
    _showBanner(
      avatarName: n.displayName,
      avatarUrl: n.displayAvatarUrl,
      isPage: n.isFromPage,
      title: null,
      body: n.text,
      onOpen: () => switch (n.type) {
        _ when n.isAboutPost => openPost(context, n.postId!),
        ActivityType.followRequest => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const ActivityScreen())),
        _ => openProfile(context, n.actor.id),
      },
    );
  }

  StreamSubscription<DmNotification>? _dmAlerts;
  Timer? _bannerTimer;

  /// In-app alert for a new message, on top of whatever screen is open.
  void _showDmBanner(DmNotification alert) => _showBanner(
    avatarName: alert.sender.name,
    avatarUrl: alert.sender.avatarUrl,
    title: alert.sender.name,
    body: alert.preview,
    onOpen: () => openChat(context, alert.sender),
  );

  void _showBanner({
    required String avatarName,
    required String? avatarUrl,
    bool isPage = false,
    required String? title,
    required String body,
    required VoidCallback onOpen,
  }) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    void hide() {
      _bannerTimer?.cancel();
      messenger.hideCurrentMaterialBanner();
    }

    messenger
      ..hideCurrentMaterialBanner()
      ..showMaterialBanner(
        MaterialBanner(
          backgroundColor: kCardWhite,
          elevation: 3,
          leading: isPage
              ? PageAvatar(name: avatarName, url: avatarUrl)
              : UserAvatar(name: avatarName, url: avatarUrl),
          content: Text.rich(
            TextSpan(
              children: [
                if (title != null)
                  TextSpan(
                    text: '$title\n',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                TextSpan(text: body),
              ],
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            TextButton(onPressed: hide, child: const Text('Dismiss')),
            TextButton(
              onPressed: () {
                hide();
                onOpen();
              },
              child: const Text('Open'),
            ),
          ],
        ),
      );
    _bannerTimer?.cancel();
    _bannerTimer = Timer(const Duration(seconds: 6), hide);
  }

  @override
  void dispose() {
    _syncErrors?.cancel();
    _dmAlerts?.cancel();
    _activityAlerts?.cancel();
    _bannerTimer?.cancel();
    super.dispose();
  }

  void _openComposer() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            ComposerScreen(onBack: () => Navigator.of(context).pop()),
      ),
    );
  }

  Widget _buildBody() {
    return switch (_selectedIndex) {
      1 => const GroupsScreen(),
      3 => const SearchScreen(),
      4 => const ProfileScreen(),
      _ => HomeScreen(
        onOpenComposer: _openComposer,
        onOpenMessages: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const DirectMessagesScreen())),
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCream,
      body: _buildBody(),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        child: Container(
          height: 72,
          decoration: BoxDecoration(
            color: kCardWhite,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: _NavIconButton(
                  icon: Icons.home_rounded,
                  selected: _selectedIndex == 0,
                  onTap: () => setState(() => _selectedIndex = 0),
                ),
              ),
              Expanded(
                child: _NavIconButton(
                  icon: Icons.groups_rounded,
                  selected: _selectedIndex == 1,
                  onTap: () => setState(() => _selectedIndex = 1),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: _openComposer,
                  child: Container(
                    width: 58,
                    height: 58,
                    margin: const EdgeInsets.only(top: 7, bottom: 7),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: kGreen,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x2A059669),
                          blurRadius: 18,
                          offset: Offset(0, 7),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.add_rounded,
                      color: kWhite,
                      size: 30,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _NavIconButton(
                  icon: Icons.search_rounded,
                  selected: _selectedIndex == 3,
                  onTap: () => setState(() => _selectedIndex = 3),
                ),
              ),
              Expanded(
                child: _NavIconButton(
                  icon: Icons.person_outline_rounded,
                  selected: _selectedIndex == 4,
                  onTap: () => setState(() => _selectedIndex = 4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavIconButton extends StatelessWidget {
  const _NavIconButton({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: Icon(
          icon,
          color: selected ? kGreen : const Color(0xFF8B93A3),
          size: 24,
        ),
      ),
    );
  }
}
