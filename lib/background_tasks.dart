import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import 'alert_logic.dart';
import 'db.dart';
import 'notification_service.dart';
import 'scraper.dart';

const stockBackgroundCheckTask = 'stockBackgroundCheckTask';

/// Android WorkManager 기반 백그라운드 점검.
///
/// 제한사항:
/// - Android 주기 작업 최소 간격은 보통 15분 수준이며 1분 단위 보장은 불가
/// - 제조사/배터리 최적화 정책에 따라 지연될 수 있음
/// - iOS에서는 현재 프로젝트 범위상 상시 백그라운드 크롤링을 보장하지 않음
class BackgroundTasks {
  BackgroundTasks._();
  static final BackgroundTasks instance = BackgroundTasks._();

  Future<void> registerPeriodicSync() async {
    await Workmanager().registerPeriodicTask(
      'stock-background-worker',
      stockBackgroundCheckTask,
      frequency: const Duration(minutes: 15),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      initialDelay: const Duration(minutes: 15),
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 15),
    );
  }
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();

    await NotificationService.instance.init();
    final scraper = NaverFinanceScraper();
    final watchlist = await AppDb.instance.listWatchlist();

    for (final t in watchlist) {
      final previous = await AppDb.instance.latestPrice(t.code);
      final p = await scraper.fetchOne(t);
      if (p == null) continue;

      await AppDb.instance.insertPrice(p);

      if (shouldTriggerAlert(
        ticker: t,
        currentPrice: p.price,
        previousPrice: previous?.price,
      )) {
        await NotificationService.instance.showTargetReached(
          ticker: t,
          price: p,
        );
        await AppDb.instance.markAlertTriggered(t.code, true);
      }
    }

    return true;
  });
}
