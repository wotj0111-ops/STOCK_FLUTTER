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
    'Accept-Language': 'ko-KR,ko;q=0.9',
  };

  /// 종목코드 → 종목명 (UTF-8 개별 페이지)
  Future<String?> lookupName(String code) async {
    final html = await _fetchHtml(code);
    if (html == null) return null;
    final m = RegExp(
      r'class="wrap_company".*?<h2>\s*<a[^>]*>([^<]+)</a>',
      dotAll: true,
    ).firstMatch(html);
    return m?.group(1)?.trim();
  }

  /// 종목명 부분일치 검색 (LIKE 스타일).
  /// 네이버 금융 자동완성 JSON API. 부분 문자열도 매칭됨.
  Future<List<Ticker>> searchByName(String keyword) async {
    final q = keyword.trim();
    if (q.isEmpty) return [];
    final url = Uri.parse(
      'https://ac.finance.naver.com/ac'
      '?q=${Uri.encodeQueryComponent(q)}'
      '&q_enc=utf-8&st=111&frm=stock&r_format=json&r_enc=utf-8&r_unicode=0&t_koreng=1',
    );
    try {
      final r = await http
          .get(url, headers: _headers)
          .timeout(const Duration(seconds: 6));
      if (r.statusCode != 200) return [];
      final body = utf8.decode(r.bodyBytes, allowMalformed: true);
      final data = json.decode(body) as Map<String, dynamic>;
      final items = <Ticker>[];
      final seen = <String>{};

      // 실제 응답 구조: { "items": [ [ [["삼성전자"], ..., ["005930"], ...], ... ] ] }
      // 카테고리마다 스키마가 살짝 달라서, 배열을 재귀 탐색해서
      // "6자리 코드"와 그 근처의 "종목명" 후보를 쌍으로 뽑는다.
      final groups = data['items'] as List? ?? [];
      for (final g in groups) {
        if (g is! List) continue;
        for (final row in g) {
          if (row is! List) continue;
          String? code;
          String? name;

          for (final field in row) {
            final v = _firstString(field);
            if (v == null) continue;
            if (code == null && RegExp(r'^\d{6}$').hasMatch(v)) {
              code = v;
              continue;
            }
            // 종목명 후보: 한글/영문/숫자 포함, 6자리 순수숫자는 제외
            if (name == null &&
                RegExp(r'[가-힣A-Za-z]').hasMatch(v) &&
                !RegExp(r'^\d+$').hasMatch(v) &&
                v.length <= 30) {
              name = v;
            }
          }

          if (code != null && name != null && seen.add(code)) {
            items.add(Ticker(code: code, name: name));
            if (items.length >= 15) break;
          }
        }
        if (items.length >= 15) break;
      }

      // 부분일치 랭킹: 이름이 keyword로 시작하는 것을 앞으로
      items.sort((a, b) {
        int score(String n) {
          if (n == q) return 0;
          if (n.startsWith(q)) return 1;
          if (n.contains(q)) return 2;
          return 3;
        }

        return score(a.name).compareTo(score(b.name));
      });
      return items;
    } catch (_) {
      return [];
    }
  }

  /// 리스트가 중첩된 형태에서 첫 문자열을 재귀로 찾는다.
  String? _firstString(dynamic node) {
    if (node is String) return node;
    if (node is List && node.isNotEmpty) {
      for (final e in node) {
        final s = _firstString(e);
        if (s != null) return s;
      }
    }
    return null;
  }

  /// 6자리 숫자면 코드 검색, 아니면 이름(부분일치) 검색.
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
