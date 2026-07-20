import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 앱 진입 시 알림 채널을 초기화하고 권한을 요청.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    const androidInit = AndroidInitializationSettings('ic_notification');
    const initSettings = InitializationSettings(android: androidInit);
    await _plugin.initialize(initSettings);
    _initialized = true;
  }

  Future<void> requestPermissions() async {
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (e) {
      if (kDebugMode) debugPrint('[notif] requestPermissions 실패: $e');
    }
  }
}
