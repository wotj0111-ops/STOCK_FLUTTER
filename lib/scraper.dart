import 'dart:convert';
import 'package:http/http.dart' as http;
import 'models.dart';

class SearchDiag {
  final String source;   // 'ac' | 'sise' | 'mstock' | 'none'
  final int httpCode;
  final int rawBytes;
  final int parsedCount;
  final String? error;
  SearchDiag({
    required this.source,
    required this.httpCode,
    required this.rawBytes,
    required this.parsedCount,
    this.error,
  });

  @override
  String toString() =>
      'src=$source http=$httpCode bytes=$rawBytes count=$parsedCount'
      '${error == null ? '' : ' err=$error'}';
}

class SearchResult {
  final List<Ticker> items;
  final List<SearchDiag> diags;
  SearchResult(this.items, this.diags);
}

class NaverFinanceScraper {
  static const _desktopUa =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0 Safari/537.36';

  static const _headersDesktop = {
    'User-Agent': _desktopUa,
    'Referer': 'https://finance.naver.com/',
    'Origin': 'https://finance.naver.com',
    'Accept': 'application/json,text/plain,*/*',
    'Accept-Language': 'ko-KR,ko;q=0.9',
  };

  static const _headersMobile = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 12; Pixel) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36',
    'Referer': 'https://m.stock.naver.com/',
    'Accept': 'application/json,text/plain,*/*',
    'Accept-Language': 'ko-KR,ko;q=0.9',
  };

  /// 종목코드 → 종목명
  Future<String?> lookupName(String code) async {
    final url =
        Uri.parse('https://finance.naver.com/item/main.naver?code=$code');
    try {
      final r = await http
          .get(url, headers: _headersDesktop)
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

  /// 종목명 부분일치 검색 — 3단계 폴백.
  /// 성공한 단계까지의 결과와 진단 정보를 함께 반환.
  Future<SearchResult> searchByNameDiag(String keyword) async {
    final q = keyword.trim();
    if (q.isEmpty) return SearchResult(const [], const []);

    final diags = <SearchDiag>[];

    // ── 1) ac.finance.naver.com (데스크톱 프리셋)
    try {
      final url = Uri.parse(
        'https://ac.finance.naver.com/ac'
        '?q=${Uri.encodeQueryComponent(q)}'
        '&q_enc=utf-8&st=111&frm=stock&r_format=json&r_enc=utf-8'
        '&r_unicode=0&t_koreng=1',
      );
      final r = await http
          .get(url, headers: _headersDesktop)
          .timeout(const Duration(seconds: 6));
      final bytes = r.bodyBytes.length;
      if (r.statusCode == 200 && bytes > 0) {
        final items = _parseAcFinance(r.bodyBytes, q);
        diags.add(SearchDiag(
            source: 'ac', httpCode: r.statusCode, rawBytes: bytes, parsedCount: items.length));
        if (items.isNotEmpty) return SearchResult(items, diags);
      } else {
        diags.add(SearchDiag(
            source: 'ac', httpCode: r.statusCode, rawBytes: bytes, parsedCount: 0));
      }
    } catch (e) {
      diags.add(SearchDiag(
          source: 'ac', httpCode: -1, rawBytes: 0, parsedCount: 0, error: e.toString()));
    }

    // ── 2) 모바일 네이버 증권 자동완성 (m.stock.naver.com)
    try {
      final url = Uri.parse(
        'https://m.stock.naver.com/api/search/autoComplete'
        '?keyword=${Uri.encodeQueryComponent(q)}',
      );
      final r = await http
          .get(url, headers: _headersMobile)
          .timeout(const Duration(seconds: 6));
      final bytes = r.bodyBytes.length;
      if (r.statusCode == 200 && bytes > 0) {
        final items = _parseMStock(r.bodyBytes, q);
        diags.add(SearchDiag(
            source: 'mstock', httpCode: r.statusCode, rawBytes: bytes, parsedCount: items.length));
        if (items.isNotEmpty) return SearchResult(items, diags);
      } else {
        diags.add(SearchDiag(
            source: 'mstock', httpCode: r.statusCode, rawBytes: bytes, parsedCount: 0));
      }
    } catch (e) {
      diags.add(SearchDiag(
          source: 'mstock', httpCode: -1, rawBytes: 0, parsedCount: 0, error: e.toString()));
    }

    // ── 3) finance.naver.com/api/sise/search.nhn (구 내부 API)
    try {
      final url = Uri.parse(
        'https://finance.naver.com/api/sise/search.nhn'
        '?keyword=${Uri.encodeQueryComponent(q)}',
      );
      final r = await http
          .get(url, headers: _headersDesktop)
          .timeout(const Duration(seconds: 6));
      final bytes = r.bodyBytes.length;
      if (r.statusCode == 200 && bytes > 0) {
        final items = _parseSise(r.bodyBytes, q);
        diags.add(SearchDiag(
            source: 'sise', httpCode: r.statusCode, rawBytes: bytes, parsedCount: items.length));
        if (items.isNotEmpty) return SearchResult(items, diags);
      } else {
        diags.add(SearchDiag(
            source: 'sise', httpCode: r.statusCode, rawBytes: bytes, parsedCount: 0));
      }
    } catch (e) {
      diags.add(SearchDiag(
          source: 'sise', httpCode: -1, rawBytes: 0, parsedCount: 0, error: e.toString()));
    }

    return SearchResult(const [], diags);
  }

  /// 기존 호환용 (진단 정보 없이 목록만)
  Future<List<Ticker>> searchByName(String keyword) async {
    final r = await searchByNameDiag(keyword);
    return r.items;
  }

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

  // ─── 파서들 ──────────────────────────────────────────────

  List<Ticker> _parseAcFinance(List<int> bodyBytes, String q) {
    final body = utf8.decode(bodyBytes, allowMalformed: true);
    dynamic data;
    try {
      data = json.decode(body);
    } catch (_) {
      return const [];
    }
    if (data is! Map) return const [];
    final results = <Ticker>[];
    final seen = <String>{};
    void visit(dynamic node) {
      if (node is List) {
        String? code, name;
        for (final e in node) {
          final s = _firstString(e);
          if (s == null) continue;
          if (code == null && RegExp(r'^\d{6}$').hasMatch(s)) code = s;
          else if (name == null &&
              RegExp(r'[가-힣A-Za-z]').hasMatch(s) &&
              !RegExp(r'^\d+$').hasMatch(s) &&
              s.length <= 30) name = s;
        }
        if (code != null && name != null && seen.add(code)) {
          results.add(Ticker(code: code, name: name));
        }
        for (final e in node) visit(e);
      } else if (node is Map) {
        for (final v in node.values) visit(v);
      }
    }
    visit(data);
    return _rank(results, q);
  }

  List<Ticker> _parseMStock(List<int> bodyBytes, String q) {
    final body = utf8.decode(bodyBytes, allowMalformed: true);
    dynamic data;
    try {
      data = json.decode(body);
    } catch (_) {
      return const [];
    }
    // m.stock.naver.com 응답은 대체로:
    // { "result": { "items": [ { "cd":"005930", "nm":"삼성전자", ... }, ... ] } }
    List list = const [];
    if (data is Map) {
      final res = data['result'];
      if (res is Map && res['items'] is List) list = res['items'] as List;
      else if (data['items'] is List) list = data['items'] as List;
    }
    final out = <Ticker>[];
    final seen = <String>{};
    for (final e in list) {
      if (e is! Map) continue;
      final code = (e['cd'] ?? e['code'] ?? e['itemCode'])?.toString();
      final name = (e['nm'] ?? e['name'] ?? e['korName'] ?? e['itemName'])?.toString();
      if (code == null || name == null) continue;
      if (!RegExp(r'^\d{6}$').hasMatch(code)) continue;
      if (seen.add(code)) out.add(Ticker(code: code, name: name));
    }
    return _rank(out, q);
  }

  List<Ticker> _parseSise(List<int> bodyBytes, String q) {
    final body = utf8.decode(bodyBytes, allowMalformed: true);
    dynamic data;
    try {
      data = json.decode(body);
    } catch (_) {
      return const [];
    }
    // finance.naver.com/api/sise/search.nhn 응답:
    // { "result": { "d": [ { "cd":"005930", "nm":"삼성전자" }, ... ] } }
    List list = const [];
    if (data is Map) {
      final res = data['result'];
      if (res is Map) {
        if (res['d'] is List) list = res['d'] as List;
        else if (res['items'] is List) list = res['items'] as List;
      }
    }
    final out = <Ticker>[];
    final seen = <String>{};
    for (final e in list) {
      if (e is! Map) continue;
      final code = (e['cd'] ?? e['code'])?.toString();
      final name = (e['nm'] ?? e['name'])?.toString();
      if (code == null || name == null) continue;
      if (!RegExp(r'^\d{6}$').hasMatch(code)) continue;
      if (seen.add(code)) out.add(Ticker(code: code, name: name));
    }
    return _rank(out, q);
  }

  List<Ticker> _rank(List<Ticker> items, String q) {
    items.sort((a, b) {
      int score(String n) {
        if (n == q) return 0;
        if (n.startsWith(q)) return 1;
        if (n.contains(q)) return 2;
        return 3;
      }
      return score(a.name).compareTo(score(b.name));
    });
    return items.take(15).toList();
  }

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

  // ─── 시세 (기존과 동일) ─────────────────────────────────

  Future<PricePoint?> fetchOne(Ticker t) async {
    final url =
        Uri.parse('https://finance.naver.com/item/main.naver?code=${t.code}');
    try {
      final r = await http
          .get(url, headers: _headersDesktop)
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
        if (block.contains('no_up')) sign = 1;
        else if (block.contains('no_down')) sign = -1;
        final nums = RegExp(r'<span class="blind">([\d,\.]+)</span>')
            .allMatches(block)
            .map((m) => m.group(1)!)
            .toList();
        if (nums.isNotEmpty) signedChange = sign * _toInt(nums.first);
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
