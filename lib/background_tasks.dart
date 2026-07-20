import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart' as wm;

import 'alert_logic.dart';
import 'db.dart';
import 'models.dart';
import 'notification_service.dart';
import 'scraper.dart';

const String kStockBackgroundCheckTask = 'stockBackgroundCheckTask';

@pragma('vm:entry-point')
void callbackDispatcher() {
  wm.Workmanager().executeTask((task, inputData) async {
    try {
      if (task != kStockBackgroundCheckTask) {
        return Future.value(true);
      }

      final db = AppDb.instance;
      final scraper = NaverFinanceScraper();
      final notifier = NotificationService.instance;

      await notifier.init();

      final List<Ticker> tickers = await db.listWatchlist();

      for (final Ticker t in tickers) {
        try {
          final price = await scraper.fetchOne(t);
          if (price == null) continue;

          await db.insertPrice(price);

          if (t.alertEnabled &&
              t.alertPrice != null &&
              !t.alertTriggered &&
              shouldTriggerAlert(
                ticker: t,
                currentPrice: price.price,
              )) {
            // ✅ named 인자로 호출
            await notifier.showTargetReached(
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
