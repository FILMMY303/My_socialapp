import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/models.dart';
import '../../data/repository_scope.dart';
import '../navigation.dart';
import '../widgets/common_widgets.dart';
import '../widgets/feed_list.dart';
import 'follow_list_screen.dart';

/// Search people by name, or posts by #tag.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';
  Future<List<Profile>>? _people;

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      final query = value.trim();
      setState(() {
        _query = query;
        _people = query.isEmpty || query.startsWith('#')
            ? null
            : RepositoryScope.servicesOf(context).profiles.searchUsers(query);
      });
    });
  }

  bool get _isTag => _query.startsWith('#') && _query.length > 1;

  /// The query as a tag (without '#' or spaces).
  String get _tag =>
      _query.replaceAll('#', '').split(RegExp(r'\s+')).first.toLowerCase();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Text(
              'Search',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: kMainText,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              onChanged: _onChanged,
              decoration: InputDecoration(
                hintText: 'Search people, or #tag for posts',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _controller.clear();
                          _onChanged('');
                        },
                      ),
                filled: true,
                fillColor: kCardWhite,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(child: _buildResults()),
          ],
        ),
      ),
    );
  }

  Widget _buildResults() {
    if (_query.isEmpty) {
      return Center(
        child: Text(
          'Find people by name or username,\nor posts by #hashtag.',
          textAlign: TextAlign.center,
          style: TextStyle(color: kSecondaryText),
        ),
      );
    }
    if (_isTag) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '#$_tag',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: kGreen,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => openTag(context, _tag),
                child: const Text('Open'),
              ),
            ],
          ),
          Expanded(
            child: FeedList(
              key: ValueKey(_tag),
              scope: FeedScope.tag(_tag),
              emptyText: 'No posts with #$_tag yet.',
            ),
          ),
        ],
      );
    }
    return FutureBuilder<List<Profile>>(
      future: _people,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ErrorRetry(
            message: errorMessage(snapshot.error!),
            onRetry: () => _onChanged(_controller.text),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: kGreen));
        }
        final people = snapshot.data!;
        return ListView(
          children: [
            if (people.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('No people found.')),
              ),
            for (final person in people) ProfileTile(profile: person),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.tag_rounded, color: kGreen),
              title: Text('Posts tagged #${_tag.replaceAll(' ', '')}'),
              onTap: () => openTag(context, _tag),
            ),
          ],
        );
      },
    );
  }
}
