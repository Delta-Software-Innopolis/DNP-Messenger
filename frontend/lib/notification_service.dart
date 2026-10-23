import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const AndroidNotificationChannel _androidChannel =
      AndroidNotificationChannel(
        'messages',
        'Messages',
        description: 'Incoming messenger messages',
        importance: Importance.high,
      );

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
      ),
    );

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.createNotificationChannel(_androidChannel);
    await androidPlugin?.requestNotificationsPermission();

    final iosPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    await iosPlugin?.requestPermissions(alert: true, badge: true, sound: true);

    _initialized = true;
  }

  Future<void> showMessage({
    required String id,
    required String title,
    required String body,
  }) async {
    await initialize();

    final notificationDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        _androidChannel.id,
        _androidChannel.name,
        channelDescription: _androidChannel.description,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
      macOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await _plugin.show(
      _notificationIdFrom(id),
      title,
      body,
      notificationDetails,
      payload: 'message:$id',
    );
  }

  static int _notificationIdFrom(String id) {
    final numericId = int.tryParse(id);
    if (numericId != null) return numericId % 2147483647;

    return id.hashCode & 0x7fffffff;
  }

  bool get needsRuntimePermission => Platform.isAndroid || Platform.isIOS;
}
