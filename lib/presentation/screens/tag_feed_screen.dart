import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/models.dart';
import '../widgets/feed_list.dart';

/// Every visible post containing #[tag].
class TagFeedScreen extends StatelessWidget {
  const TagFeedScreen({super.key, required this.tag});

  final String tag;

  @override
  Widget build(BuildContext context) {
    final scope = FeedScope.tag(tag);
    return Scaffold(
      backgroundColor: kCream,
      appBar: AppBar(backgroundColor: kCream, title: Text('#${scope.value}')),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: FeedList(
          scope: scope,
          emptyText: 'No posts with #${scope.value} yet.',
        ),
      ),
    );
  }
}
