import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/notifications/browser_notifications.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_controller.dart';
import '../../data/models/models.dart';
import '../../data/repository_scope.dart';
import '../widgets/common_widgets.dart';
import 'blocked_users_screen.dart';
import 'edit_profile_screen.dart';
import 'group_notifications_screen.dart';

/// Account, appearance and notification settings for the signed-in user.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _openingProfile = false;

  Future<void> _editProfile() async {
    final services = RepositoryScope.servicesOf(context);
    setState(() => _openingProfile = true);
    try {
      final profile = await services.profiles.getProfile(services.userId);
      if (!mounted) return;
      final updated = await Navigator.of(context).push<Profile>(
        MaterialPageRoute(builder: (_) => EditProfileScreen(profile: profile)),
      );
      if (updated != null && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Profile updated.')));
      }
    } catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    } finally {
      if (mounted) setState(() => _openingProfile = false);
    }
  }

  Future<void> _enableBrowserNotifications() async {
    final result = await RepositoryScope.servicesOf(context)
        .notifications
        .browser
        .requestPermission();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result == NotificationPermission.granted
              ? 'You will get a notification when a message arrives while '
                    'this tab is in the background.'
              : 'Notifications are blocked. Allow them in the browser site '
                    'settings to get alerts.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final services = RepositoryScope.servicesOf(context);
    return Scaffold(
      backgroundColor: kCream,
      appBar: AppBar(
        backgroundColor: kCream,
        elevation: 0,
        title: Text(
          'Settings',
          style: TextStyle(color: kMainText, fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
        children: [
          const _SectionTitle('Account'),
          _SettingsCard(
            children: [
              _SettingsTile(
                icon: Icons.person_outline_rounded,
                title: 'Edit profile',
                subtitle: 'Name, username, bio and photo',
                trailing: _openingProfile
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: kGreen,
                        ),
                      )
                    : null,
                onTap: _openingProfile ? null : _editProfile,
              ),
              _SettingsTile(
                icon: Icons.block_rounded,
                title: 'Blocked users',
                subtitle: 'People who cannot see or message you',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const BlockedUsersScreen()),
                ),
              ),
            ],
          ),
          const _SectionTitle('Appearance'),
          _SettingsCard(
            children: [
              ValueListenableBuilder<ThemeMode>(
                valueListenable: ThemeController.instance,
                builder: (context, _, _) {
                  final dark = ThemeController.instance.isDark;
                  return _SettingsTile(
                    icon: dark
                        ? Icons.dark_mode_rounded
                        : Icons.light_mode_rounded,
                    title: 'Dark mode',
                    subtitle: dark ? 'On' : 'Off',
                    trailing: Switch(
                      value: dark,
                      activeThumbColor: kGreen,
                      onChanged: (on) => ThemeController.instance.setMode(
                        on ? ThemeMode.dark : ThemeMode.light,
                      ),
                    ),
                    onTap: ThemeController.instance.toggle,
                  );
                },
              ),
            ],
          ),
          const _SectionTitle('Notifications'),
          _SettingsCard(
            children: [
              // Browser alerts only work in desktop browsers: the phone app
              // has no browser API and mobile Chrome/Safari block them.
              if (!_isPhone)
                _browserNotificationsTile(services.notifications.browser),
              _SettingsTile(
                icon: Icons.groups_outlined,
                title: 'Groups & pages',
                subtitle: 'Choose which ones notify you about new posts',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const GroupNotificationsScreen(),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _browserNotificationsTile(BrowserNotifications browser) {
    final permission = browser.permission;
    final (subtitle, trailing) = switch (permission) {
      NotificationPermission.granted => (
        'On. You get alerts for new messages while this tab is in the '
            'background.',
        const Icon(Icons.check_circle_rounded, color: kGreen),
      ),
      NotificationPermission.notAsked => (
        'Get notified about new messages while this tab is in the background.',
        TextButton(
          onPressed: _enableBrowserNotifications,
          child: const Text('Turn on'),
        ),
      ),
      NotificationPermission.denied => (
        'Blocked. Allow notifications for this site in your browser settings.',
        Icon(Icons.notifications_off_outlined, color: kMuted),
      ),
      NotificationPermission.unsupported => (
        'Not supported on this device.',
        null,
      ),
    };
    return _SettingsTile(
      icon: Icons.notifications_active_outlined,
      title: 'Message notifications',
      subtitle: subtitle,
      trailing: trailing,
    );
  }
}

bool get _isPhone => switch (defaultTargetPlatform) {
  TargetPlatform.android || TargetPlatform.iOS => true,
  _ => false,
};

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 16, 6, 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: kSecondaryText,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

/// White rounded group of tiles separated by thin dividers.
class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kCardWhite,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                indent: 56,
                color: kMuted.withValues(alpha: 0.2),
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: kPaleGreen,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: kGreen, size: 20),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: kMainText,
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: kSecondaryText, fontSize: 12),
      ),
      trailing:
          trailing ??
          (onTap != null
              ? Icon(Icons.chevron_right_rounded, color: kMuted)
              : null),
    );
  }
}
