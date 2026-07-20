import 'dart:convert';
import 'package:http/http.dart' as http;

class StockNews {
  final String title;
  final String source;
  final String url;
  final DateTime? dateKst;
  final String snippet;

  StockNews({
    required this.title,
    required this.source,
    required this.url,
    required this.dateKst,
    required this.snippet,
  });
}

class NewsSummary {
  final List<StockNews> items;
  final List<String> keywords;
  final String headline;
  NewsSummary({
    required this.items,
    required this.keywords,
    required this.headline,
  });
}

/// Google News RSS 파서.
/// - UTF-8 XML 응답 → 인코딩 이슈 없음
/// - 각 뉴스의 <link>가 언론사 원문 URL (네이버 앱 딥링크 아님)
/// - 종목명 검색으로 관련도/최신 뉴스 확보
class StockNewsService {
  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 12; Pixel) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36',
    'Accept-Language': 'ko-KR,ko;q=0.9',
  };

  /// [query]는 종목명(예: "삼성전자")을 넘긴다.
  Future<NewsSummary> fetch(String query, {int limit = 15}) async {
    // 종목명에 큰따옴표를 감싸 정확도 UP + 한국 언론사 우선
    final q = '"$query" 주식 OR 증권 OR 실적';
    final url = Uri.parse(
      'https://news.google.com/rss/search'
      '?q=${Uri.encodeQueryComponent(q)}'
      '&hl=ko&gl=KR&ceid=KR:ko',
    );

    try {
      final r = await http
          .get(url, headers: _headers)
          .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) {
        return NewsSummary(
          items: const [],
          keywords: const [],
          headline: '뉴스를 불러올 수 없습니다.',
        );
      }
      final xml = utf8.decode(r.bodyBytes, allowMalformed: true);

      final itemRe = RegExp(r'<item>(.*?)</item>', dotAll: true);
      RegExp tagRe(String tag) => RegExp(
            '<$tag>(?:<!\\[CDATA\\[)?(.*?)(?:\\]\\]>)?</$tag>',
            dotAll: true,
          );

      final items = <StockNews>[];
      for (final m in itemRe.allMatches(xml)) {
        final body = m.group(1)!;
        final title = _decodeHtml(
            _stripTags(tagRe('title').firstMatch(body)?.group(1) ?? '').trim());
        final link = (tagRe('link').firstMatch(body)?.group(1) ?? '').trim();
        final pubDate =
            (tagRe('pubDate').firstMatch(body)?.group(1) ?? '').trim();
        final srcMatch =
            RegExp(r'<source[^>]*>(.*?)</source>', dotAll: true).firstMatch(body);
        final source = _decodeHtml(_stripTags(srcMatch?.group(1) ?? '').trim());

        if (title.isEmpty || link.isEmpty) continue;
        items.add(StockNews(
          title: title,
          source: source,
          url: link,
          dateKst: _parseRfc822ToKst(pubDate),
          snippet: '',
        ));
        if (items.length >= limit) break;
      }

      final keywords = _extractKeywords(items.map((e) => e.title).toList());
      final headline = items.isEmpty
          ? '관련 뉴스가 없습니다.'
          : _buildHeadline(items, keywords);
      return NewsSummary(items: items, keywords: keywords, headline: headline);
    } catch (_) {
      return NewsSummary(
        items: const [],
        keywords: const [],
        headline: '뉴스를 불러올 수 없습니다.',
      );
    }
  }

  /// "Sun, 20 Jul 2026 05:12:00 GMT" → KST DateTime
  DateTime? _parseRfc822ToKst(String s) {
    if (s.isEmpty) return null;
    final months = {
      'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
      'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
    };
    final m = RegExp(
      r'(\d{1,2})\s+(\w{3})\s+(\d{4})\s+(\d{2}):(\d{2}):(\d{2})',
    ).firstMatch(s);
    if (m == null) return null;
    final month = months[m.group(2)!];
    if (month == null) return null;
    final utc = DateTime.utc(
      int.parse(m.group(3)!),
      month,
      int.parse(m.group(1)!),
      int.parse(m.group(4)!),
      int.parse(m.group(5)!),
      int.parse(m.group(6)!),
    );
    return utc.add(const Duration(hours: 9));
  }

  String _stripTags(String s) =>
      s.replaceAll(RegExp(r'<[^>]+>'), '').replaceAll('&nbsp;', ' ').trim();

  String _decodeHtml(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&#39;', "'");

  List<String> _extractKeywords(List<String> titles) {
    final stop = <String>{
      '및', '등', '위해', '통해', '이번', '오늘', '올해', '내년', '지난',
      '관련', '대비', '중', '것', '수', '한', '두', '세', '억', '만', '원',
      '뉴스', '기자', '단독', '속보', '종합',
    };
    final freq = <String, int>{};
    final wordRe = RegExp(r'[가-힣A-Za-z0-9]{2,}');
    for (final t in titles) {
      for (final m in wordRe.allMatches(t)) {
        final w = m.group(0)!;
        if (stop.contains(w)) continue;
        if (RegExp(r'^\d+$').hasMatch(w)) continue;
        freq[w] = (freq[w] ?? 0) + 1;
      }
    }
    final sorted = freq.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(6).map((e) => e.key).toList();
  }

  String _buildHeadline(List<StockNews> items, List<String> keywords) {
    final now = DateTime.now();
    final recent = items
        .where((n) =>
            n.dateKst != null && now.difference(n.dateKst!).inHours <= 24)
        .length;
    final total = items.length;
    final kw =
        keywords.isEmpty ? '' : ' · 키워드: ${keywords.take(3).join(", ")}';
    return '최근 뉴스 $total건 (24시간 이내 $recent건)$kw';
  }
}
