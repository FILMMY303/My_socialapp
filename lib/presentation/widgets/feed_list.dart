import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/models.dart';
import '../../data/repositories/social_repository.dart';
import '../../data/repository_scope.dart';
import 'common_widgets.dart';
import 'post_card.dart';

/// A pull-to-refresh timeline for [scope], newest first.
///
/// Posts come from the local database immediately; the cloud copy is pulled
/// when the list opens and on pull-to-refresh.
class FeedList extends StatefulWidget {
  const FeedList({
    super.key,
    required this.scope,
    this.header,
    this.emptyText = 'No posts yet.',
    this.isGroupAdmin = false,
    this.padding = const EdgeInsets.only(bottom: 18),
  });

  final FeedScope scope;
  final Widget? header;
  final String emptyText;
  final bool isGroupAdmin;
  final EdgeInsets padding;

  @override
  State<FeedList> createState() => _FeedListState();
}

class _FeedListState extends State<FeedList> {
  SocialRepository? _repository;
  late Stream<List<FeedPost>> _feed;
  bool _loading = false;
  String? _loadError;

  // Infinite scroll: older pages are fetched near the end of the list.
  bool _hasMore = true;
  bool _loadingMore = false;
  String? _moreError;

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _loading) return;
    setState(() {
      _loadingMore = true;
      _moreError = null;
    });
    try {
      final more = await _repository!.loadMore(widget.scope);
      if (mounted) setState(() => _hasMore = more);
    } catch (error) {
      if (mounted) setState(() => _moreError = errorMessage(error));
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.extentAfter < 600 && _moreError == null) {
      _loadMore();
    }
    return false;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repository = RepositoryScope.of(context);
    if (repository != _repository) {
      _repository = repository;
      _subscribe();
    }
  }

  @override
  void didUpdateWidget(FeedList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scope != widget.scope) _subscribe();
  }

  void _subscribe() {
    _feed = _repository!.watchFeed(widget.scope);
    _loading = true;
    _hasMore = true;
    _moreError = null;
    // setState is not allowed while building; load after this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      await _repository!.refresh(widget.scope);
    } catch (error) {
      if (mounted) setState(() => _loadError = errorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pullToRefresh() async {
    try {
      await _repository!.refresh(widget.scope);
      if (mounted) {
        setState(() {
          _loadError = null;
          _hasMore = true;
          _moreError = null;
        });
      }
    } catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FeedPost>>(
      stream: _feed,
      builder: (context, snapshot) {
        final posts = snapshot.data ?? const <FeedPost>[];
        final children = <Widget>[
          ?widget.header,
          if (snapshot.hasError)
            _Message(
              text: 'Could not read saved posts: ${snapshot.error}',
              isError: true,
              onRetry: () => setState(_subscribe),
            )
          else if (posts.isEmpty && (_loading || !snapshot.hasData))
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator(color: kGreen)),
            )
          else if (posts.isEmpty && _loadError != null)
            _Message(text: _loadError!, isError: true, onRetry: _load)
          else if (posts.isEmpty)
            _Message(text: widget.emptyText),
          for (final item in posts)
            PostCard(
              key: ValueKey(item.post.id),
              item: item,
              isGroupAdmin: widget.isGroupAdmin,
            ),
          if (posts.isNotEmpty && _loadingMore)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator(color: kGreen)),
            )
          else if (posts.isNotEmpty && _moreError != null)
            _Message(
              text: _moreError!,
              isError: true,
              onRetry: () {
                setState(() => _moreError = null);
                _loadMore();
              },
            )
          else if (posts.length >= SocialRepository.pageSize && !_hasMore)
            Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: Text(
                  "You're all caught up.",
                  style: TextStyle(color: kMuted),
                ),
              ),
            ),
        ];

        return RefreshIndicator(
          color: kGreen,
          onRefresh: _pullToRefresh,
          child: NotificationListener<ScrollNotification>(
            onNotification: posts.length >= SocialRepository.pageSize
                ? _onScroll
                : null,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: widget.padding,
              itemCount: children.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, index) => children[index],
            ),
          ),
        );
      },
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.isError = false, this.onRetry});

  final String text;
  final bool isError;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 12),
      child: Column(
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: isError ? kRed : kSecondaryText),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}
