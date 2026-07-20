import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'db.dart';
import 'models.dart';

/// 종목 카탈로그: 번들 CSV + KRX 백그라운드 갱신 하이브리드.
class StockCatalog {
  StockCatalog._();
  static final StockCatalog instance = StockCatalog._();

  static const _lastFetchKey = 'stocks_last_fetched_at_v1';
  static const _refreshIntervalHours = 24 * 7; // 주 1회

  bool _initializing = false;

  /// 앱 시작 시 호출.
  /// 1) stocks 테이블 비어있으면 번들 CSV 로드
  /// 2) 마지막 갱신 후 7일 초과면 KRX 백그라운드 갱신 시도
  Future<void> initialize() async {
    if (_initializing) return;
    _initializing = true;
    try {
      final db = AppDb.instance;
      final count = await db.stocksCount();
      if (count == 0) {
        await _loadBundle();
      }
      // 백그라운드 갱신 (UI 블로킹 없음)
      _unawaited(_maybeRefreshFromKrx());
    } finally {
      _initializing = false;
    }
  }

  Future<void> _loadBundle() async {
    try {
      final csv = await rootBundle.loadString('assets/stocks.csv');
      final rows = _parseCsv(csv);
      if (rows.isNotEmpty) {
        await AppDb.instance.bulkUpsertStocks(rows);
      }
    } catch (_) {
      // 번들 파일이 없어도 앱은 시동됨
    }
  }

  Future<void> _maybeRefreshFromKrx() async {
    final sp = await SharedPreferences.getInstance();
    final last = sp.getInt(_lastFetchKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final hours = (now - last) / (1000 * 60 * 60);
    if (hours < _refreshIntervalHours) return;
    await refreshNow();
  }

  /// 수동/즉시 갱신. 성공 시 true.
  Future<bool> refreshNow() async {
    final rows = await _fetchFromKrx();
    if (rows.isEmpty) return false;
    await AppDb.instance.bulkUpsertStocks(rows);
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_lastFetchKey, DateTime.now().millisecondsSinceEpoch);
    return true;
  }

  /// KRX 정보데이터시스템에서 상장법인 전체 목록 조회.
  /// MDCSTAT01901: 상장종목 전체 (KOSPI/KOSDAQ/KONEX)
  Future<List<Map<String, Object?>>> _fetchFromKrx() async {
    const url = 'http://data.krx.co.kr/comm/bldAttendant/getJsonData.cmd';
    try {
      final r = await http.post(
        Uri.parse(url),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/124.0 Safari/537.36',
          'Referer': 'http://data.krx.co.kr/contents/MDC/MDI/mdiLoader/'
              'index.cmd?menuId=MDC0201',
          'Accept': 'application/json,*/*',
          'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        },
        body: {
          'bld': 'dbms/MDC/STAT/standard/MDCSTAT01901',
          'locale': 'ko_KR',
          'mktId': 'ALL',
          'share': '1',
          'csvxls_isNo': 'false',
        },
      ).timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return const [];
      final body = utf8.decode(r.bodyBytes, allowMalformed: true);
      final data = json.decode(body) as Map<String, dynamic>;
      final list = data['OutBlock_1'] as List? ?? const [];
      final out = <Map<String, Object?>>[];
      for (final row in list) {
        if (row is! Map) continue;
        final code = (row['ISU_SRT_CD'] ?? row['ISU_CD'])?.toString();
        final name = (row['ISU_ABBRV'] ?? row['ISU_NM'])?.toString();
        final market = (row['MKT_NM'] ?? row['MKT_TP_NM'])?.toString();
        if (code == null || name == null) continue;
        if (!RegExp(r'^\d{6}$').hasMatch(code)) continue;
        out.add({'code': code, 'name': name, 'market': market ?? ''});
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  List<Map<String, Object?>> _parseCsv(String csv) {
    final rows = <Map<String, Object?>>[];
    final lines = csv.split(RegExp(r'\r?\n'));
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      if (i == 0 && line.startsWith('code')) continue;
      final parts = line.split(',');
      if (parts.length < 2) continue;
      final code = parts[0].trim();
      final name = parts[1].trim();
      final market = parts.length >= 3 ? parts[2].trim() : '';
      if (!RegExp(r'^\d{6}$').hasMatch(code)) continue;
      if (name.isEmpty) continue;
      rows.add({'code': code, 'name': name, 'market': market});
    }
    return rows;
  }

  /// 부분일치 검색 (SQLite LIKE, 랭킹은 정확→접두→포함)
  Future<List<Ticker>> search(String query) async {
    final rows = await AppDb.instance.searchStocks(query);
    return rows
        .map((r) => Ticker(
              code: r['code'] as String,
              name: r['name'] as String,
            ))
        .toList();
  }

  Future<DateTime?> lastRefreshed() async {
    final sp = await SharedPreferences.getInstance();
    final ms = sp.getInt(_lastFetchKey);
    if (ms == null || ms == 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }
}

void _unawaited(Future<void> f) {
  f.catchError((_) {});
}
