import 'package:flutter/material.dart';

import 'background_tasks.dart';
import 'notification_service.dart';
import 'ticker_list_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 알림 초기화 및 권한 요청
  await NotificationService.instance.init();
  await NotificationService.instance.requestPermissions();

  // 백그라운드 작업 초기화 및 주기적 시세 체크 등록
  await BackgroundTasks.instance.initialize();
  await BackgroundTasks.instance.registerPeriodicSync();

  runApp(const StockApp());
}

class StockApp extends StatelessWidget {
  const StockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '내 주식 대시보드',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: const TickerListPage(),
    );
  }
}
