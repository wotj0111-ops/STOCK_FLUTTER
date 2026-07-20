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

  /// 종목코드 → 종목명 조회 (관심종목 추가 시 사용).
  /// finance.naver.com 종목 페이지는 UTF-8 이므로 이름이 깨지지 않는다.
  Future<String?> lookupName(String code) async {
    final html = await _fetchHtml(code);
    if (html == null) return null;
    final m = RegExp(
      r'class="wrap_company".*?<h2>\s*<a[^>]*>([^<]+)</a>',
      dotAll: true,
    ).firstMatch(html);
    return m?.group(1)?.trim();
  }

  /// 종목명으로 검색 → [{code, name}] 후보 반환.
  ///
  /// 자동완성 API 대신 finance.naver.com 검색 결과 페이지의 HTML 을 파싱.
  /// 검색 결과 페이지는 EUC-KR 이라 한글이 깨지지만, 우리는 코드만 뽑고
  /// 종목명은 각 코드의 UTF-8 개별 페이지에서 다시 조회해서 채운다.
  Future<List<Ticker>> searchByName(String keyword) async {
    if (keyword.trim().isEmpty) return [];
    final url = Uri.parse(
      'https://finance.naver.com/search/searchList.naver'
      '?query=${Uri.encodeQueryComponent(keyword)}',
    );
    try {
      final r = await http
          .get(url, headers: _headers)
          .timeout(const Duration(seconds: 6));
      if (r.statusCode != 200) return [];

      // 이 페이지는 EUC-KR 이므로 bytes 를 latin1 그대로 문자열화 하여
      // 정규식으로 코드만 뽑는다. 종목명 한글은 사용하지 않으므로 인코딩 무관.
      final html = String.fromCharCodes(r.bodyBytes);

      // <a href="/item/main.naver?code=005930"> ... </a>
      final codeRe = RegExp(r'href="/item/main\.naver\?code=(\d{6})"');
      final codes = <String>[];
      final seen = <String>{};
      for (final m in codeRe.allMatches(html)) {
        final code = m.group(1)!;
        if (seen.add(code)) codes.add(code);
        if (codes.length >= 10) break;
      }

      // 각 코드에 대해 이름은 UTF-8 개별 종목 페이지에서 정확히 조회.
      final results = <Ticker>[];
      for (final code in codes) {
        final name = await lookupName(code);
        if (name != null && name.isNotEmpty) {
          results.add(Ticker(code: code, name: name));
        }
      }
      return results;
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
