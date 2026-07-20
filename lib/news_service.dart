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

/// 네이버 금융 종목 뉴스 파서.
class StockNewsService {
  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 12; Pixel) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36',
    'Referer': 'https://finance.naver.com/',
  };

  Future<NewsSummary> fetch(String code, {int limit = 12}) async {
    final url = Uri.parse(
      'https://finance.naver.com/item/news_news.naver'
      '?code=$code&page=1&sm=title_entity_id.basic&clusterId=',
    );
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
    final html = utf8.decode(r.bodyBytes, allowMalformed: true);

    final rowRe = RegExp(
      r'<tr[^>]*>\s*<td[^>]*class="title"[^>]*>\s*<a[^>]*href="([^"]+)"[^>]*>(.*?)</a>'
      r'.*?<td[^>]*class="info"[^>]*>(.*?)</td>'
      r'.*?<td[^>]*class="date"[^>]*>(.*?)</td>',
      dotAll: true,
    );

    final items = <StockNews>[];
    for (final m in rowRe.allMatches(html)) {
      final href = m.group(1)!;
      final title = _decodeHtml(_stripTags(m.group(2)!)).trim();
      final source = _decodeHtml(_stripTags(m.group(3)!)).trim();
      final dateStr = _stripTags(m.group(4)!).trim();
      final fullUrl =
          href.startsWith('http') ? href : 'https://finance.naver.com$href';
      final date = _parseKstDate(dateStr);

      items.add(StockNews(
        title: title,
        source: source,
        url: fullUrl,
        dateKst: date,
        snippet: '',
      ));
      if (items.length >= limit) break;
    }

    final keywords = _extractKeywords(items.map((e) => e.title).toList());
    final headline = items.isEmpty
        ? '오늘 관련 뉴스가 없습니다.'
        : _buildHeadline(items, keywords);

    return NewsSummary(items: items, keywords: keywords, headline: headline);
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

  DateTime? _parseKstDate(String s) {
    final m = RegExp(r'(\d{4})\.(\d{2})\.(\d{2})\s+(\d{2}):(\d{2})')
        .firstMatch(s);
    if (m == null) return null;
    return DateTime(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
      int.parse(m.group(4)!),
      int.parse(m.group(5)!),
    );
  }

  List<String> _extractKeywords(List<String> titles) {
    final stop = <String>{
      '및', '등', '위해', '통해', '이번', '오늘', '올해', '내년',
      '지난', '관련', '대비', '중', '것', '수', '한', '두', '세',
      '억', '만', '원', '가', '나', '을', '를', '이', '가',
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
        .where(
            (n) => n.dateKst != null && now.difference(n.dateKst!).inHours <= 24)
        .length;
    final total = items.length;
    final kw =
        keywords.isEmpty ? '' : ' · 키워드: ${keywords.take(3).join(", ")}';
    return '최근 뉴스 $total건 (24시간 이내 $recent건)$kw';
  }
}
