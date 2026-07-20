import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';

import 'background_tasks.dart';
import 'notification_service.dart';
import 'ticker_list_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.init();
  await NotificationService.instance.requestPermissions();
  await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
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
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
      ),
      home: const TickerListPage(),
    );
  }
}
