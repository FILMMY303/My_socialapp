enum NotificationPermission { granted, denied, notAsked, unsupported }

class BrowserNotifications {
  const BrowserNotifications();

  NotificationPermission get permission => NotificationPermission.unsupported;

  /// Whether the app is the visible tab/window.
  bool get isPageVisible => true;

  Future<NotificationPermission> requestPermission() async =>
      NotificationPermission.unsupported;

  void show({
    required String title,
    required String body,
    String? icon,
    String? tag,
    void Function()? onClick,
  }) {}
}
