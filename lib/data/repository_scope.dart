import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'repositories/social_repository.dart';
import 'services/activity_service.dart';
import 'services/block_service.dart';
import 'services/chat_service.dart';
import 'services/group_service.dart';
import 'services/media_service.dart';
import 'services/notification_service.dart';
import 'services/profile_service.dart';
import 'services/report_service.dart';
import 'services/saved_service.dart';

/// Everything the signed-in user's screens need.
///
/// - [repository]: posts, comments, reactions; offline-first
///   (local DB + outbox).
/// - The services: online only (profiles, follows, groups, chat, media,
///   reports).
class AppServices {
  AppServices({required this.repository, required SupabaseClient client})
    : media = MediaService(client, repository.userId),
      profiles = ProfileService(client, repository.userId),
      groups = GroupService(client, repository.userId),
      reports = ReportService(client, repository.userId) {
    chat = ChatService(client, repository.userId, profiles);
    notifications = NotificationService(client, repository.userId, profiles);
    activity = ActivityService(client, repository.userId);
    saved = SavedService(client, repository.userId);
    blocks = BlockService(client, repository.userId, profiles);
  }

  final SocialRepository repository;
  final MediaService media;
  final ProfileService profiles;
  final GroupService groups;
  final ReportService reports;
  late final ChatService chat;
  late final NotificationService notifications;
  late final ActivityService activity;
  late final SavedService saved;
  late final BlockService blocks;

  String get userId => repository.userId;

  Future<void> dispose() async {
    notifications.dispose();
    activity.dispose();
    saved.dispose();
    blocks.dispose();
    await repository.dispose();
  }
}

/// Makes the signed-in user's [AppServices] available to the widget tree.
class RepositoryScope extends InheritedWidget {
  const RepositoryScope({
    super.key,
    required this.services,
    required super.child,
  });

  final AppServices services;

  static AppServices servicesOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<RepositoryScope>();
    assert(scope != null, 'No RepositoryScope found in context');
    return scope!.services;
  }

  static SocialRepository of(BuildContext context) =>
      servicesOf(context).repository;

  @override
  bool updateShouldNotify(RepositoryScope oldWidget) =>
      services != oldWidget.services;
}
