/// One login notification (DIGI `digi_rest_api/login_notifications`).
/// Fields mirror the API response object.
class LoginNotification {
  final int notificationId;
  final String title;
  final String body; // content_html — rich text / HTML
  final int durationMin;
  final int durationSec;

  const LoginNotification({
    this.notificationId = 0,
    required this.title,
    required this.body,
    this.durationMin = 0,
    this.durationSec = 0,
  });

  /// Auto-close duration. `Duration.zero` (both min & sec = 0) means the popup
  /// stays open until the user dismisses it.
  Duration get autoClose =>
      Duration(minutes: durationMin, seconds: durationSec);

  factory LoginNotification.fromJson(Map<String, dynamic> j) {
    int toInt(dynamic v) => v is int ? v : int.tryParse('${v ?? ''}') ?? 0;
    return LoginNotification(
      notificationId: toInt(j['notification_id']),
      title: '${j['title'] ?? 'Notifications'}',
      body: '${j['content_html'] ?? ''}',
      durationMin: toInt(j['duration_min']),
      durationSec: toInt(j['duration_sec']),
    );
  }
}
