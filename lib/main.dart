import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/storage/preferences.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/theme_controller.dart';
import 'data/local/local_database.dart';
import 'data/remote/remote_data_source.dart';
import 'data/repositories/social_repository.dart';
import 'data/repository_scope.dart';
import 'presentation/screens/activity_screen.dart';
import 'presentation/screens/auth_screen.dart';
import 'presentation/screens/chat_screen.dart';
import 'presentation/screens/my_social_home.dart';
import 'presentation/screens/reset_password_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Before the first frame, so the saved theme is used from the start.
  await loadPreferences();

  try {
    await dotenv.load(fileName: '.env');
  } catch (error, stackTrace) {
    debugPrint('Could not load .env configuration: $error\n$stackTrace');
    runApp(SupabaseInitializationErrorApp(error: error.toString()));
    return;
  }

  final supabaseUrl = dotenv.env['SUPABASE_URL']?.trim() ?? '';
  final supabasePublishableKey =
      dotenv.env['SUPABASE_PUBLISHABLE_KEY']?.trim() ?? '';

  if (supabaseUrl.isEmpty || supabasePublishableKey.isEmpty) {
    runApp(const SupabaseSetupApp());
    return;
  }

  try {
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabasePublishableKey,
    );
    runApp(const MySocialApp());
  } catch (error, stackTrace) {
    debugPrint('Supabase initialization failed: $error\n$stackTrace');
    runApp(SupabaseInitializationErrorApp(error: error.toString()));
  }
}

class MySocialApp extends StatelessWidget {
  const MySocialApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.instance,
      builder: (context, mode, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'MySocial',
        themeMode: mode,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        home: const AuthGate(),
      ),
    );
  }

  static ThemeData _theme(Brightness brightness) {
    final palette = brightness == Brightness.dark
        ? AppPalette.dark
        : AppPalette.light;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: palette.background,
      fontFamily: 'Inter',
      colorScheme: ColorScheme.fromSeed(
        seedColor: kGreen,
        brightness: brightness,
        primary: kGreen,
        surface: palette.surface,
        onSurface: palette.mainText,
      ),
    );
  }
}

class SupabaseSetupApp extends StatelessWidget {
  const SupabaseSetupApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const _SupabaseStatusApp(
      title: 'Supabase is not configured',
      message:
          'Run the app with --dart-define=SUPABASE_URL=... and '
          '--dart-define=SUPABASE_ANON_KEY=... using your Supabase project values.',
    );
  }
}

class SupabaseInitializationErrorApp extends StatelessWidget {
  const SupabaseInitializationErrorApp({super.key, required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return _SupabaseStatusApp(
      title: 'Could not connect to Supabase',
      message: error,
    );
  }
}

class _SupabaseStatusApp extends StatelessWidget {
  const _SupabaseStatusApp({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                SelectableText(message, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late Session? _session;

  /// True after the user opened a password reset link, until they set a new
  /// password or sign out.
  bool _recovering = false;
  late final StreamSubscription<AuthState> _authSubscription;

  @override
  void initState() {
    super.initState();
    final auth = Supabase.instance.client.auth;
    _session = auth.currentSession;
    _authSubscription = auth.onAuthStateChange.listen((state) {
      if (!mounted) return;
      setState(() {
        _session = state.session;
        if (state.event == AuthChangeEvent.passwordRecovery) {
          _recovering = true;
        } else if (state.event == AuthChangeEvent.signedOut) {
          _recovering = false;
        }
      });
    });
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = _session?.user;
    if (user == null) return const AuthScreen();
    if (_recovering) {
      return ResetPasswordScreen(
        onDone: () => setState(() => _recovering = false),
      );
    }
    return _SignedInApp(key: ValueKey(user.id), user: user);
  }
}

/// Opens the local database for [user] and keeps one repository per sign-in.
class _SignedInApp extends StatefulWidget {
  const _SignedInApp({super.key, required this.user});

  final User user;

  @override
  State<_SignedInApp> createState() => _SignedInAppState();
}

class _SignedInAppState extends State<_SignedInApp> {
  late Future<AppServices> _servicesFuture;
  AppServices? _services;

  @override
  void initState() {
    super.initState();
    _servicesFuture = _open();
  }

  Future<AppServices> _open() async {
    final user = widget.user;
    final client = Supabase.instance.client;
    final metadataName = user.userMetadata?['username']?.toString().trim();
    final services = AppServices(
      client: client,
      repository: SocialRepository(
        local: await LocalDatabase.open(user.id),
        remote: SupabaseRemoteDataSource(client),
        userId: user.id,
        username: metadataName?.isNotEmpty == true
            ? metadataName!
            : user.email?.split('@').first ?? 'User',
      ),
    );
    if (!mounted) {
      await services.dispose();
      return services;
    }
    _services = services;
    // Live DM notifications; tapping a browser notification opens the chat.
    services.notifications
      ..onOpenChat = ((sender) {
        _navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => ChatScreen(partner: sender)),
        );
      })
      ..start();
    services.activity
      ..onOpen = ((_) {
        _navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => const ActivityScreen()),
        );
      })
      ..start();
    unawaited(services.saved.load().catchError((_) {}));
    unawaited(services.blocks.load().catchError((_) {}));
    // Show cached data at once; cloud data arrives in the background.
    unawaited(services.repository.refresh().catchError((_) {}));
    // The profile row is the source of truth for the username.
    unawaited(
      services.profiles
          .getProfile(user.id)
          .then((p) {
            services.repository
              ..username = p.username
              ..avatarUrl = p.avatarUrl;
          })
          .catchError((_) {}),
    );
    return services;
  }

  @override
  void dispose() {
    _services?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppServices>(
      future: _servicesFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _LocalDatabaseError(
            error: snapshot.error!,
            onRetry: () => setState(() {
              _servicesFuture = _open();
            }),
          );
        }
        final services = snapshot.data;
        if (services == null) {
          return Scaffold(
            backgroundColor: kCream,
            body: Center(child: CircularProgressIndicator(color: kGreen)),
          );
        }
        // A nested navigator keeps pushed screens inside RepositoryScope.
        return RepositoryScope(
          services: services,
          child: NavigatorPopHandler(
            onPopWithResult: (_) => _navigatorKey.currentState?.maybePop(),
            child: Navigator(
              key: _navigatorKey,
              onGenerateRoute: (_) =>
                  MaterialPageRoute(builder: (_) => const MySocialHome()),
            ),
          ),
        );
      },
    );
  }

  final _navigatorKey = GlobalKey<NavigatorState>();
}

class _LocalDatabaseError extends StatelessWidget {
  const _LocalDatabaseError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCream,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Could not open local storage',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text('$error', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              TextButton(onPressed: onRetry, child: const Text('Try again')),
              TextButton(
                onPressed: () => Supabase.instance.client.auth.signOut(),
                child: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
