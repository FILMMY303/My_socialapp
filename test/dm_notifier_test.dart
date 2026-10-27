import 'package:appsocial/core/notifications/browser_notifications.dart';
import 'package:appsocial/data/models/models.dart';
import 'package:appsocial/data/services/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeBrowser implements BrowserNotifications {
  bool visible = true;
  final shown = <String>[];

  @override
  bool get isPageVisible => visible;

  @override
  NotificationPermission get permission => NotificationPermission.granted;

  @override
  Future<NotificationPermission> requestPermission() async => permission;

  @override
  void show({
    required String title,
    required String body,
    String? icon,
    String? tag,
    void Function()? onClick,
  }) => shown.add('$title: $body');
}

ChatMessage message(String from, {String to = 'me', String text = 'hi'}) =>
    ChatMessage(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      senderId: from,
      receiverId: to,
      text: text,
      createdAt: DateTime.now(),
    );

void main() {
  late FakeBrowser browser;
  late DmNotifier notifier;
  late List<DmNotification> alerts;

  setUp(() {
    browser = FakeBrowser();
    notifier = DmNotifier(
      userId: 'me',
      loadProfile: (id) async => Profile(id: id, username: 'user_$id'),
      browser: browser,
    );
    alerts = [];
    notifier.events.listen(alerts.add);
  });

  tearDown(() => notifier.dispose());

  Future<void> flush() => Future<void>.delayed(Duration.zero);

  test(
    'a new message shows an in-app alert while the app is visible',
    () async {
      await notifier.handleIncoming(message('ann', text: 'hello'));
      await flush();
      expect(alerts.single.sender.username, 'user_ann');
      expect(alerts.single.preview, 'hello');
      expect(browser.shown, isEmpty);
    },
  );

  test('a background tab gets a browser notification instead', () async {
    browser.visible = false;
    await notifier.handleIncoming(message('ann', text: 'hello'));
    await flush();
    expect(alerts, isEmpty);
    expect(browser.shown.single, 'user_ann: hello');
  });

  test('muted people never notify', () async {
    notifier.muted.value = {'ann'};
    await notifier.handleIncoming(message('ann'));
    browser.visible = false;
    await notifier.handleIncoming(message('ann'));
    await flush();
    expect(alerts, isEmpty);
    expect(browser.shown, isEmpty);
    expect(notifier.isMuted('ann'), isTrue);

    await notifier.handleIncoming(message('bob'));
    expect(browser.shown, hasLength(1));
  });

  test('no alert for the chat that is open on screen', () async {
    notifier.activeChatPartnerId = 'ann';
    await notifier.handleIncoming(message('ann'));
    await notifier.handleIncoming(message('bob'));
    await flush();
    expect(alerts.map((a) => a.sender.id), ['bob']);
  });

  test('own messages and media previews', () async {
    await notifier.handleIncoming(message('me', to: 'ann'));
    await notifier.handleIncoming(
      ChatMessage(
        id: 'v',
        senderId: 'ann',
        receiverId: 'me',
        text: '',
        createdAt: DateTime.now(),
        media: const MediaRef(url: 'me/ann/v.mp4', type: MediaType.video),
      ),
    );
    await flush();
    expect(alerts.single.preview, 'Sent a video');
  });
}
