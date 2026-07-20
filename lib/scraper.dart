import 'dart:convert';
import 'package:http/http.dart' as http;

import 'models.dart';
import 'stock_catalog.dart';

/// 시세 크롤러 + 종목 검색(카탈로그 기반).
class NaverFinanceScraper {
  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/124.0 Safari/537.36',
    'Referer': 'https://finance.naver.com/',
    'Accept-Language': 'ko-KR,ko;q=0.9',
  };

  /// 종목코드 → 종목명. 카탈로그 우선, 실패 시 네이버 페이지 조회.
  Future<String?> lookupName(String code) async {
    final catalog = await StockCatalog.instance.search(code);
    for (final t in catalog) {
      if (t.code == code) return t.name;
    }
    try {
      final url =
          Uri.parse('https://finance.naver.com/item/main.naver?code=$code');
      final r = await http
          .get(url, headers: _headers)
          .timeout(const Duration(seconds: 6));
      if (r.statusCode != 200) return null;
      final html = utf8.decode(r.bodyBytes, allowMalformed: true);
      final m = RegExp(
        r'class="wrap_company".*?<h2>\s*<a[^>]*>([^<]+)</a>',
        dotAll: true,
      ).firstMatch(html);
      return m?.group(1)?.trim();
    } catch (_) {
      return null;
    }
  }

  /// 종목명(부분일치) 검색 — 100% 로컬 카탈로그.
  Future<List<Ticker>> searchByName(String keyword) =>
      StockCatalog.instance.search(keyword);

  /// 코드/이름 자동 분기.
  Future<List<Ticker>> smartSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    if (RegExp(r'^\d{6}$').hasMatch(q)) {
      final cat = await StockCatalog.instance.search(q);
      if (cat.isNotEmpty) return cat;
      final name = await lookupName(q);
      if (name != null) return [Ticker(code: q, name: name)];
      return [];
    }
    return searchByName(q);
  }

  /// 종목 하나의 현재 시세를 가져와 PricePoint 로 반환.
  Future<PricePoint?> fetchOne(Ticker t) async {
    final url =
        Uri.parse('https://finance.naver.com/item/main.naver?code=${t.code}');
    try {
      final r = await http
          .get(url, headers: _headers)
          .timeout(const Duration(seconds: 6));
      if (r.statusCode != 200) return null;
      final html = utf8.decode(r.bodyBytes, allowMalformed: true);

      final mPrice = RegExp(
        r'<p class="no_today">.*?<span class="blind">([\d,]+)</span>',
        dotAll: true,
      ).firstMatch(html);
      if (mPrice == null) return null;
      final price = _toInt(mPrice.group(1)!);

      int signedChange = 0;
      final mExday = RegExp(
        r'<p class="no_exday">(.*?)</p>',
        dotAll: true,
      ).firstMatch(html);
      if (mExday != null) {
        final block = mExday.group(1)!;
        int sign = 0;
        if (block.contains('no_up')) {
          sign = 1;
        } else if (block.contains('no_down')) {
          sign = -1;
        }
        final nums = RegExp(r'<span class="blind">([\d,\.]+)</span>')
            .allMatches(block)
            .map((m) => m.group(1)!)
            .toList();
        if (nums.isNotEmpty) {
          signedChange = sign * _toInt(nums.first);
        }
      }

      final prevClose = price - signedChange;
      final changePct = (prevClose != 0)
          ? double.parse((signedChange / prevClose * 100).toStringAsFixed(2))
          : 0.0;

      final mVol = RegExp(r'거래량\s*([\d,]+)').firstMatch(html);
      final volume = mVol != null ? _toInt(mVol.group(1)!) : null;

      return PricePoint(
        tsKst: DateTime.now().toUtc().add(const Duration(hours: 9)),
        code: t.code,
        name: t.name,
        price: price,
        change: signedChange,
        changePct: changePct,
        volume: volume,
      );
    } catch (_) {
      return null;
    }
  }

  int _toInt(String s) {
    final cleaned = s.replaceAll(RegExp(r'[^\d\-]'), '');
    if (cleaned.isEmpty || cleaned == '-') return 0;
    return int.parse(cleaned);
  }
}
