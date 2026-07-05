import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
  FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: (details) {
        debugPrint('Notification tapped: ${details.payload}');
      },
    );

    // Create channel on Android.
    final androidPlugin =
    _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    // Android locks vibration/sound into the channel at creation time, so a new
    // channel id is required to drop vibration. Remove the old vibrating channel.
    await androidPlugin?.deleteNotificationChannel('payment_channel_v4');
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'payment_channel_v5',
        'Payment Notifications',
        description: 'Payment success alerts',
        importance: Importance.max,
        playSound: false, // fully silent — no sound
        enableVibration: false, // and no vibration
      ),
    );

    _initialized = true;
    debugPrint('NotificationService: init complete');
  }

  static Future<bool> _ensurePermission() async {
    final androidPlugin =
    _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      // Notification permission is requested ONCE at login
      // (login_screen._requestPermissions → Permission.notification). Do NOT
      // re-prompt on the payment path — only CHECK. If it isn't granted, silently
      // skip the success notification (a best-effort extra; Android shows no
      // post-payment system notification at all). This stops the permission popup
      // from re-appearing after every payment.
      final alreadyEnabled = await androidPlugin.areNotificationsEnabled();
      debugPrint('NotificationService: areNotificationsEnabled=$alreadyEnabled');
      return alreadyEnabled == true;
    }

    // iOS
    final iosPlugin =
    _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();

    if (iosPlugin != null) {
      final granted = await iosPlugin.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted == true;
    }

    return true; // other platforms assume ok
  }

  static Future<void> showPaymentNotification({
    required String title,
    required String body,
  }) async {
    await init();

    final permitted = await _ensurePermission();
    debugPrint('NotificationService: permitted=$permitted');

    if (!permitted) {
      debugPrint('NotificationService: no permission — cannot show notification');
      return;
    }

    try {
      final id = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      await _plugin.show(
        id,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'payment_channel_v5',
            'Payment Notifications',
            channelDescription: 'Payment success alerts',
            importance: Importance.max,
            priority: Priority.high,
            playSound: false, // fully silent — no sound
            enableVibration: false, // and no vibration
            visibility: NotificationVisibility.public,
            icon: '@mipmap/ic_launcher',
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: false,
          ),
        ),
      );

      debugPrint('NotificationService: shown successfully id=$id');
    } catch (e, st) {
      debugPrint('NotificationService: FAILED — $e\n$st');
    }
  }
}