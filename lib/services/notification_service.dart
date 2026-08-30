import 'dart:ui';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;

class NotificationService {
  static final _notifications = FlutterLocalNotificationsPlugin();

  static Future init() async {
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );

    await _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();

    await _notifications.initialize(settings);

    tz.initializeTimeZones();

    try {
      final String timeZoneName = DateTime.now().timeZoneName;
      tz.setLocalLocation(tz.getLocation('UTC'));
    } catch (e) {
      tz.setLocalLocation(tz.getLocation('UTC'));
    }
  }

  static Future scheduleCollectionAlert() async {
    const instantDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        'instant_channel_id',
        'Request Updates',
        channelDescription: 'Immediate feedback for collection requests',
        importance: Importance.max,
        priority: Priority.high,
        color: Color(0xFF00E676),
      ),
    );

    await _notifications.show(
      1, // Unique ID for instant notification
      'AuraSync: Request Logged! 📨',
      'Your specialized waste pickup has been synced with the local collector.',
      instantDetails,
    );

    // 2. SCHEDULED NOTIFICATION
    await _notifications.zonedSchedule(
      0,
      'AuraSync: Collector Incoming! 🚛',
      'The specialized toxic waste collector will visit your area in 48 hours. Get your swarm ready!',
      // Using UTC for the demo to guarantee it works on every device
      tz.TZDateTime.now(tz.UTC).add(const Duration(seconds: 10)),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'channel_id',
          'Collection Alerts',
          importance: Importance.max,
          priority: Priority.high,
          showWhen: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }
}
