import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart' as wm;

import 'alert_logic.dart';
import 'db.dart';
import 'models.dart';
import 'notification_service.dart';
import 'scraper.dart';

/// WorkManager에 등록될 task 고유 이름
const String kStockBackgroundCheckTask = 'stockBackgroundCheckTask';

/// 백그라운드에서 실행되는 진입점.
/// Android가 앱을 종료해도 이 함수가 호출됩니다.
@pragma('vm:entry-point')
void callbackDispatcher() {
  wm.Workmanager().executeTask((task, inputData) async {
    try {
      if (task != kStockBackgroundCheckTask) {
        return Future.value(true);
      }

      final db = AppDb.instance;
      final scraper = NaverFinanceScraper();
      final notifier = NotificationService();

      // 알림 채널 초기화 (앱이 종료된 상태에서도 필요)
      await notifier.init();

      final tickers = await db.listWatchlist();

      for (final Ticker t in tickers) {
        try {
          final price = await scraper.fetchOne(t.code);
          if (price == null) continue;

          await db.insertPrice(price);

          // 알림 조건 검사
          if (t.alertEnabled &&
              t.alertPrice != null &&
              !t.alertTriggered &&
              shouldTriggerAlert(t, price.price)) {
            await notifier.showTargetReached(t, price.price);
            await db.markAlertTriggered(t.code, true);
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[bg] ${t.code} 처리 실패: $e');
          }
          // 개별 종목 실패는 무시하고 다음 종목 진행
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

/// 백그라운드 작업 관리 클래스
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

  /// 주기적 시세 체크 등록.
  /// Android WorkManager는 최소 15분 주기까지만 지원합니다.
  Future<void> registerPeriodicCheck({
    Duration frequency = const Duration(minutes: 15),
  }) async {
    await wm.Workmanager().registerPeriodicTask(
      kStockBackgroundCheckTask,
      kStockBackgroundCheckTask,
      frequency: frequency,
      existingWorkPolicy: wm.ExistingPeriodicWorkPolicy.update,
      constraints: wm.Constraints(
        networkType: wm.NetworkType.connected,
        requiresBatteryNotLow: false,
        requiresCharging: false,
        requiresDeviceIdle: false,
        requiresStorageNotLow: false,
      ),
      backoffPolicy: wm.BackoffPolicy.linear,
      backoffPolicyDelay: const Duration(minutes: 1),
      initialDelay: const Duration(seconds: 30),
    );
  }

  /// 등록 해제
  Future<void> cancelAll() async {
    await wm.Workmanager().cancelAll();
  }
}
