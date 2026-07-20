import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart' as wm;

import 'alert_logic.dart';
import 'db.dart';
import 'models.dart';
import 'notification_service.dart';
import 'scraper.dart';

/// WorkManager에 등록되는 task 고유 이름
const String kStockBackgroundCheckTask = 'stockBackgroundCheckTask';

/// 백그라운드 실행 진입점 (앱이 종료돼 있어도 호출됨)
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
          // ✅ 실제 시그니처에 맞춰 Ticker를 그대로 전달
          final price = await scraper.fetchOne(t);
          if (price == null) continue;

          await db.insertPrice(price);

          // ✅ named 파라미터 방식으로 호출
          if (t.alertEnabled &&
              t.alertPrice != null &&
              !t.alertTriggered &&
              shouldTriggerAlert(
                ticker: t,
                currentPrice: price.price,
              )) {
            await notifier.showTargetReached(t, price.price);
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

/// 백그라운드 작업 관리 싱글턴
class BackgroundTasks {
  BackgroundTasks._();
  static final BackgroundTasks instance = BackgroundTasks._();

  bool _initialized = false;

  /// 앱 시작 시 1회 호출
  Future<void> initialize({bool debug = false}) async {
    if (_initialized) return;
    await wm.Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: debug,
    );
    _initialized = true;
  }

  /// 주기적 시세 체크 등록 (Android 최소 15분)
  ///
  /// `main.dart` 호환을 위해 `registerPeriodicSync`와 `registerPeriodicCheck`
  /// 두 이름을 모두 제공합니다.
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
      // ⚠️ existingWorkPolicy 는 workmanager 버전에 따라 enum 이름이
      // (ExistingWorkPolicy / ExistingPeriodicWorkPolicy) 로 다릅니다.
      // 빌드 호환성을 위해 여기서는 지정하지 않습니다.
      // 필요 시 pubspec.yaml 의 workmanager 버전 확인 후 다시 추가하세요.
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
