import 'dart:convert';
import 'package:http/http.dart' as http;
import 'models.dart';

/// 네이버 금융 종목 페이지를 직접 파싱하는 Dart 크롤러.
/// ⚠️ 네이버 금융은 공식 API 가 아니므로 개인 학습/모니터링용으로만 사용.
class NaverFinanceScraper {
  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 12; Pixel) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36',
    'Referer': 'https://finance.naver.com/',
  };

  /// 종목코드 → 종목명 조회 (관심종목 추가 시 사용).
  Future<String?> lookupName(String code) async {
    final html = await _fetchHtml(code);
    if (html == null) return null;
    final m = RegExp(
      r'class="wrap_company".*?<h2>\s*<a[^>]*>([^<]+)</a>',
      dotAll: true,
    ).firstMatch(html);
    return m?.group(1)?.trim();
  }

  /// 종목명(회사명)으로 검색 → [{code, name}] 후보 반환.
  /// 네이버 금융 자동완성 API 사용.
  Future<List<Ticker>> searchByName(String keyword) async {
    if (keyword.trim().isEmpty) return [];
    final url = Uri.parse(
      'https://ac.finance.naver.com/ac?q=${Uri.encodeQueryComponent(keyword)}'
      '&q_enc=UTF-8&t_koreng=1&st=111&r_format=json&r_enc=UTF-8&r_unicode=0'
      '&t_nm=a&r_lt=111',
    );
    try {
      final r = await http
          .get(url, headers: _headers)
          .timeout(const Duration(seconds: 6));
      if (r.statusCode != 200) return [];
      final decoded = utf8.decode(r.bodyBytes, allowMalformed: true);
      final data = json.decode(decoded) as Map<String, dynamic>;
      final items = <Ticker>[];
      final groups = data['items'] as List<dynamic>? ?? [];
      for (final g in groups) {
        if (g is! List) continue;
        for (final row in g) {
          if (row is! List) continue;
          final nameArr = row.isNotEmpty ? row[0] : null;
          final codeArr = row.length > 1 ? row[1] : null;
          if (nameArr is List &&
              codeArr is List &&
              nameArr.isNotEmpty &&
              codeArr.isNotEmpty) {
            final name = nameArr[0].toString();
            final code = codeArr[0].toString();
            if (RegExp(r'^\d{6}$').hasMatch(code)) {
              items.add(Ticker(code: code, name: name));
            }
          }
        }
      }
      final seen = <String>{};
      return items.where((e) => seen.add(e.code)).take(10).toList();
    } catch (_) {
      return [];
    }
  }

  /// 6자리 숫자면 코드 검색, 아니면 이름 검색.
  Future<List<Ticker>> smartSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    if (RegExp(r'^\d{6}$').hasMatch(q)) {
      final name = await lookupName(q);
      if (name != null) return [Ticker(code: q, name: name)];
      return [];
    }
    return searchByName(q);
  }

  /// 종목 하나의 현재 시세를 가져와 PricePoint 로 반환.
  Future<PricePoint?> fetchOne(Ticker t) async {
    final html = await _fetchHtml(t.code);
    if (html == null) return null;

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
  }

  Future<String?> _fetchHtml(String code) async {
    final url =
        Uri.parse('https://finance.naver.com/item/main.naver?code=$code');
    try {
      final r = await http
          .get(url, headers: _headers)
          .timeout(const Duration(seconds: 6));
      if (r.statusCode != 200) return null;
      return utf8.decode(r.bodyBytes, allowMalformed: true);
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
