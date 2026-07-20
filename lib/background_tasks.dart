import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart' as wm;

import 'db.dart';
import 'models.dart';
import 'scraper.dart';

const String kStockBackgroundCheckTask = 'stockBackgroundCheckTask';

bool _shouldTrigger({
  required Ticker ticker,
  required int currentPrice,
}) {
  final target = ticker.alertPrice;
  if (target == null) return false;
  final avg = ticker.avgPrice;

  if (avg == null) {
    return currentPrice >= target;
  }
  if (target >= avg) {
    return currentPrice >= target;
  } else {
    return currentPrice <= target;
  }
}

Future<void> _sendLocalAlert({
  required Ticker ticker,
  required int currentPrice,
}) async {
  final plugin = FlutterLocalNotificationsPlugin();

  const androidInit = AndroidInitializationSettings('ic_notification');
  const initSettings = InitializationSettings(android: androidInit);
  await plugin.initialize(initSettings);

  const androidDetails = AndroidNotificationDetails(
    'stock_alerts',
    '주식 알림',
    channelDescription: '설정한 목표가 도달 시 알림',
    importance: Importance.high,
    priority: Priority.high,
  );
  const details = NotificationDetails(android: androidDetails);

  final title = '${ticker.name} 목표가 도달';
  final body = '현재가 $currentPrice / 목표가 ${ticker.alertPrice}';

  await plugin.show(
    ticker.code.hashCode & 0x7fffffff,
    title,
    body,
    details,
  );
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  wm.Workmanager().executeTask((task, inputData) async {
    try {
      if (task != kStockBackgroundCheckTask) {
        return Future.value(true);
      }

      final db = AppDb.instance;
      final scraper = NaverFinanceScraper();

      final List<Ticker> tickers = await db.listWatchlist();

      for (final Ticker t in tickers) {
        try {
          final price = await scraper.fetchOne(t);
          if (price == null) continue;

          await db.insertPrice(price);

          if (t.alertEnabled &&
              t.alertPrice != null &&
              !t.alertTriggered &&
              _shouldTrigger(
                ticker: t,
                currentPrice: price.price,
              )) {
            await _sendLocalAlert(
              ticker: t,
              currentPrice: price.price,
            );
            await db.markAlertTriggered(t.code, true);
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[bg] ${t.code} 처리 실패: $e');
          }
          continue;
        }
      }
      return Future.value(true);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[bg] 전체 실패: $e');
      }
      return Future.value(false);
    }
  });
}

class BackgroundTasks {
  BackgroundTasks._();
  static final BackgroundTasks instance = BackgroundTasks._();

  bool _initialized = false;

  Future<void> initialize({bool debug = false}) async {
    if (_initialized) return;
    await wm.Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: debug,
    );
    _initialized = true;
  }

  Future<void> registerPeriodicSync({
    Duration frequency = const Duration(minutes: 15),
  }) =>
      _registerPeriodic(frequency);

  Future<void> registerPeriodicCheck({
    Duration frequency = const Duration(minutes: 15),
  }) =>
      _registerPeriodic(frequency);

  Future<void> _registerPeriodic(Duration frequency) async {
    await wm.Workmanager().registerPeriodicTask(
      kStockBackgroundCheckTask,
      kStockBackgroundCheckTask,
      frequency: frequency,
      initialDelay: const Duration(seconds: 30),
      constraints: wm.Constraints(
        networkType: wm.NetworkType.connected,
      ),
      backoffPolicy: wm.BackoffPolicy.linear,
      backoffPolicyDelay: const Duration(minutes: 1),
    );
  }

  Future<void> cancelAll() async {
    await wm.Workmanager().cancelAll();
  }
}
