import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'models.dart';

/// 로컬 알림 서비스.
///
/// 주의: 현재 앱 구조에서는 백그라운드 상시 수집을 하지 않으므로,
/// 알림은 앱이 열려 있는 동안의 주기적 조회 또는 수동 새로고침 시점에 발생한다.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const android = AndroidInitializationSettings('ic_notification');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(android: android, iOS: ios);
    await _plugin.initialize(settings);
  }

  Future<void> requestPermissions() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();

    final ios =
        _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    await ios?.requestPermissions(alert: true, badge: true, sound: true);

    final mac = _plugin.resolvePlatformSpecificImplementation<
        MacOSFlutterLocalNotificationsPlugin>();
    await mac?.requestPermissions(alert: true, badge: true, sound: true);
  }

  Future<void> showTargetReached({
    required Ticker ticker,
    required PricePoint price,
  }) async {
    final target = ticker.alertPrice;
    if (target == null) return;

    final android = AndroidNotificationDetails(
      'stock_price_alerts',
      '주가 알림',
      channelDescription: '관심종목 목표가 도달 알림',
      importance: Importance.max,
      priority: Priority.high,
      icon: 'ic_notification',
      ticker: ticker.name,
    );

    const ios = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(android: android, iOS: ios);

    final id = ticker.code.hashCode & 0x7fffffff;
    final body =
        '현재가 ${_fmt(price.price)}원 · 설정가 ${_fmt(target)}원\n${_reachText(price.price, target)}';

    await _plugin.show(
      id,
      '${ticker.name} 목표가 도달',
      body,
      details,
      payload: ticker.code,
    );
  }

  String _fmt(int value) {
    final s = value.toString();
    final chars = s.split('').reversed.toList();
    final out = <String>[];
    for (var i = 0; i < chars.length; i++) {
      if (i > 0 && i % 3 == 0) out.add(',');
      out.add(chars[i]);
    }
    return out.reversed.join();
  }

  String _reachText(int price, int target) {
    if (price == target) return '설정가에 정확히 도달했습니다.';
    if (price > target) return '설정가를 상향 돌파했습니다.';
    return '설정가를 하향 돌파했습니다.';
  }
}
