import 'package:appsocial/data/local/local_database.dart';
import 'package:appsocial/data/models/models.dart';
import 'package:appsocial/data/remote/remote_data_source.dart';
import 'package:appsocial/data/repositories/social_repository.dart';
import 'package:appsocial/data/repository_scope.dart';
import 'package:appsocial/data/sync/outbox_operation.dart';
import 'package:appsocial/presentation/screens/composer_screen.dart';
import 'package:appsocial/presentation/screens/my_social_home.dart';
import 'package:appsocial/presentation/screens/settings_screen.dart';
import 'package:appsocial/core/theme/theme_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Cloud that is always unreachable, so screens show their error states.
class OfflineRemote implements RemoteDataSource {
  OfflineRemote(this.feed);

  final List<Map<String, dynamic>> feed;
  bool online = true;

  @override
  Future<void> apply(OutboxOperation operation) async {}

  @override
  Future<List<Map<String, dynamic>>> fetchFeed(
    FeedScope scope, {
    int limit = 50,
    DateTime? before,
  }) async => [
    for (final row in feed)
      if (scope.matches(row)) row,
  ];
}

void main() {
  late AppServices services;
  late SupabaseClient client;

  setUp(() async {
    final repository = SocialRepository(
      local: await LocalDatabase.openWith(newDatabaseFactoryMemory(), 's.db'),
      remote: OfflineRemote([
        {
          'id': 'p1',
          'user_id': 'other',
          'username': 'alice',
          'content': 'Hello #flutter friends',
          'created_at': '2026-10-01T00:00:00Z',
          'group_id': null,
          'tags': ['flutter'],
          'media_url': 'https://example.com/a.jpg',
          'media_type': 'image',
          'comments': [],
          'post_reactions': [
            {'post_id': 'p1', 'user_id': 'me', 'type': 'love'},
          ],
        },
        {
          'id': 'p2',
          'user_id': 'me',
          'username': 'me',
          'content': '',
          'created_at': '2026-10-02T00:00:00Z',
          'group_id': null,
          'tags': [],
          'media_url': 'https://example.com/v.mp4',
          'media_type': 'video',
        },
      ]),
      userId: 'me',
      username: 'me',
      retryInterval: Duration.zero,
    );
    // Never reached: requests fail fast in the test environment.
    client = SupabaseClient('http://localhost:1', 'test-key');
    services = AppServices(repository: repository, client: client);
  });

  Widget app(Widget child) => MaterialApp(
    home: RepositoryScope(
      services: services,
      child: Navigator(
        onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => child),
      ),
    ),
  );

  /// Closes realtime connections so no reconnect timers outlive the test.
  Future<void> shutDown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await client.removeAllChannels();
      await client.dispose();
    });
    await tester.pump(const Duration(minutes: 1));
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('home feed renders posts with media and reactions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app(const MySocialHome()));
    await settle(tester);

    expect(find.text('alice'), findsOneWidget);
    expect(find.text('Love'), findsOneWidget); // my reaction on p1
    expect(find.textContaining('❤️'), findsWidgets);
    expect(tester.takeException(), isNull);

    // Every bottom tab builds without layout errors.
    for (final icon in [
      Icons.groups_rounded,
      Icons.search_rounded,
      Icons.person_outline_rounded,
      Icons.home_rounded,
    ]) {
      // The bottom bar is built after the page body.
      await tester.tap(find.byIcon(icon).last);
      await settle(tester);
      expect(tester.takeException(), isNull, reason: 'tab $icon');
    }
    await shutDown(tester);
  });

  testWidgets('composer validates empty posts', (tester) async {
    await tester.pumpWidget(app(ComposerScreen(onBack: () {})));
    await tester.tap(find.text('Post'));
    await tester.pump();
    expect(find.text('Write something or add a photo/video.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings lists account, theme and notification options', (
    tester,
  ) async {
    await tester.pumpWidget(app(const SettingsScreen()));
    await tester.pump();

    expect(find.text('Edit profile'), findsOneWidget);
    expect(find.text('Blocked users'), findsOneWidget);
    // Tests run as Android: browser alerts are hidden on phones.
    expect(find.text('Message notifications'), findsNothing);
    expect(find.text('Groups & pages'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(ThemeController.instance.value, ThemeMode.dark);
    ThemeController.instance.setMode(ThemeMode.light);
    await tester.pump();

    await tester.tap(find.text('Blocked users'));
    await settle(tester);
    expect(find.text('Blocked users'), findsWidgets);
    expect(tester.takeException(), isNull);
    await shutDown(tester);
  });

  testWidgets('desktop settings show browser message notifications', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await tester.pumpWidget(app(const SettingsScreen()));
    await tester.pump();
    expect(find.text('Message notifications'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
    await shutDown(tester);
  });
}
