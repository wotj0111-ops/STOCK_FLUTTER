import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart' as wm;

import 'db.dart';
import 'models.dart';
import 'notification_service.dart';
import 'scraper.dart';

const String kStockBackgroundCheckTask = 'stockBackgroundCheckTask';

/// 알림 조건: 저장된 알림가에 도달했는지 판정.
/// - 알림가 >= 평단가  : 현재가가 알림가 이상으로 오르면 발동 (익절)
/// - 알림가 <  평단가  : 현재가가 알림가 이하로 내리면 발동 (손절)
/// - 평단가 미설정      : 현재가가 알림가에 도달만 하면 발동
bool _shouldTrigger({
  required Ticker ticker,
  required double currentPrice,
}) {
  final target = ticker.alertPrice;
  if (target == null) return false;
  final avg = ticker.avgPrice;

  if (avg == null) {
    // 평단가가 없으면 목표가에 근접/도달만 확인
    return currentPrice >= target;
  }

  if (target >= avg) {
    // 익절 알림
    return currentPrice >= target;
  } else {
    // 손절 알림
    return currentPrice <= target;
  }
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
              _shouldTrigger(
                ticker: t,
                currentPrice: price.price,
              )) {
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
