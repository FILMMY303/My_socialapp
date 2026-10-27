import 'package:flutter/material.dart';

import '../data/models/models.dart';
import 'screens/chat_screen.dart';
import 'screens/group_detail_screen.dart';
import 'screens/post_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/tag_feed_screen.dart';

/// Pushes screens on the signed-in navigator (inside RepositoryScope).
Future<void> openProfile(BuildContext context, String userId) =>
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => ProfileScreen(userId: userId)));

Future<void> openGroup(BuildContext context, String groupId) => Navigator.of(
  context,
).push(MaterialPageRoute(builder: (_) => GroupDetailScreen(groupId: groupId)));

Future<void> openChat(BuildContext context, Profile partner) =>
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => ChatScreen(partner: partner)));

Future<void> openPost(BuildContext context, String postId) =>
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => PostScreen(postId: postId)));

Future<void> openTag(BuildContext context, String tag) =>
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => TagFeedScreen(tag: tag)));
