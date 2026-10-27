String timeAgo(DateTime timestamp) {
  final local = timestamp.toLocal();
  final elapsed = DateTime.now().difference(local);
  if (elapsed.inMinutes < 1) return 'Just now';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes} min';
  if (elapsed.inDays < 1) return '${elapsed.inHours} hr';
  if (elapsed.inDays < 7) return '${elapsed.inDays} d';
  return '${local.day}/${local.month}/${local.year}';
}

String initialOf(String name) =>
    name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
