import 'dart:convert';
import 'package:http/http.dart' as http;
import 'models.dart';

/// 네이버 금융 종목 페이지를 직접 파싱하는 Dart 크롤러.
///
/// 원 Python `scraper.py` 의 fetch_one() 을 그대로 포팅한 것.
/// 앞선 통합 테스트에서 확인된 실제 HTML 구조를 그대로 사용:
///  - 현재가:  <p class="no_today"> ... <span class="blind">259,000</span>
///  - 전일대비: <p class="no_exday"> ... no_up/no_down + <span class="blind">숫자</span>
///  - 거래량:  <dd>거래량 12,494,230</dd>
///  - 응답 인코딩은 UTF-8 (선언과 무관하게 강제 지정 필요)
///
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
    // <div class="wrap_company"><h2><a ...>삼성전자</a></h2>
    final m = RegExp(
      r'class="wrap_company".*?<h2>\s*<a[^>]*>([^<]+)</a>',
      dotAll: true,
    ).firstMatch(html);
    return m?.group(1)?.trim();
  }

  /// 종목 하나의 현재 시세를 가져와 PricePoint 로 반환.
  Future<PricePoint?> fetchOne(Ticker t) async {
    final html = await _fetchHtml(t.code);
    if (html == null) return null;

    // 현재가
    final mPrice = RegExp(
      r'<p class="no_today">.*?<span class="blind">([\d,]+)</span>',
      dotAll: true,
    ).firstMatch(html);
    if (mPrice == null) return null;
    final price = _toInt(mPrice.group(1)!);

    // 전일대비 블록만 잘라내서 방향/절대값 판별
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

    // 거래량: <dd>거래량 12,494,230</dd>
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
      final r =
          await http.get(url, headers: _headers).timeout(const Duration(seconds: 6));
      if (r.statusCode != 200) return null;
      // 네이버 금융은 실제로 UTF-8 로 응답 → bodyBytes 를 강제로 UTF-8 디코드
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
