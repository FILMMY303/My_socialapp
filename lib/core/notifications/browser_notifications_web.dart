import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

enum NotificationPermission { granted, denied, notAsked, unsupported }

class BrowserNotifications {
  const BrowserNotifications();

  bool get _supported => web.window.has('Notification');

  NotificationPermission get permission {
    if (!_supported) return NotificationPermission.unsupported;
    return _parse(web.Notification.permission);
  }

  /// Whether the app is the visible tab/window.
  bool get isPageVisible =>
      web.document.visibilityState == 'visible' && web.document.hasFocus();

  Future<NotificationPermission> requestPermission() async {
    if (!_supported) return NotificationPermission.unsupported;
    try {
      final result = await web.Notification.requestPermission().toDart;
      return _parse(result.toDart);
    } catch (_) {
      return NotificationPermission.denied;
    }
  }

  void show({
    required String title,
    required String body,
    String? icon,
    String? tag,
    void Function()? onClick,
  }) {
    if (permission != NotificationPermission.granted) return;
    try {
      final notification = web.Notification(
        title,
        web.NotificationOptions(body: body, icon: icon ?? '', tag: tag ?? ''),
      );
      notification.onclick = ((web.Event _) {
        web.window.focus();
        notification.close();
        onClick?.call();
      }).toJS;
    } catch (_) {
      // Some browsers only allow notifications from a service worker;
      // the in-app banner still shows.
    }
  }

  static NotificationPermission _parse(String value) => switch (value) {
    'granted' => NotificationPermission.granted,
    'denied' => NotificationPermission.denied,
    _ => NotificationPermission.notAsked,
  };
}
