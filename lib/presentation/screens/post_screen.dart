import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/models.dart';
import '../widgets/feed_list.dart';

/// A single post (e.g. opened from a notification).
class PostScreen extends StatelessWidget {
  const PostScreen({super.key, required this.postId});

  final String postId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCream,
      appBar: AppBar(backgroundColor: kCream, title: const Text('Post')),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: FeedList(
          scope: FeedScope.ids([postId]),
          emptyText: 'This post was deleted or is no longer visible to you.',
        ),
      ),
    );
  }
}
