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

/// 네이버 뉴스 모바일 검색 파서.
/// - UTF-8 응답이라 한글 인코딩 문제 없음
/// - 각 뉴스 카드에 언론사 원문 URL이 그대로 붙어 있어
///   네이버 증권 앱 딥링크 팝업이 뜨지 않음
class StockNewsService {
  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 12; Pixel) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36',
    'Accept-Language': 'ko-KR,ko;q=0.9',
    'Referer': 'https://m.naver.com/',
  };

  /// [query] 는 종목명(예: "삼성전자")을 넘긴다.
  Future<NewsSummary> fetch(String query, {int limit = 12}) async {
    final url = Uri.parse(
      'https://m.search.naver.com/search.naver'
      '?where=m_news&sm=mtb_jum&query=${Uri.encodeQueryComponent(query)}',
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
    // 네이버 뉴스 검색은 UTF-8.
    final html = utf8.decode(r.bodyBytes, allowMalformed: true);

    // 언론사별 원문 링크 (뉴스 검색 결과의 제목 앵커)
    // 여러 클래스 스킴을 동시에 매칭.
    final titleRe = RegExp(
      r'<a[^>]+class="[^"]*(?:news_tit|api_txt_lines total_tit|sub_tit)[^"]*"[^>]*'
      r'href="([^"]+)"[^>]*(?:title="([^"]+)"[^>]*)?>(.*?)</a>',
      dotAll: true,
    );

    final items = <StockNews>[];
    final seenUrl = <String>{};
    for (final m in titleRe.allMatches(html)) {
      final href = m.group(1)!;
      final titleAttr = m.group(2);
      final inner = _stripTags(m.group(3) ?? '');
      final title = _decodeHtml((titleAttr ?? inner).trim());
      if (title.isEmpty) continue;

      // 네이버 뉴스 자체 상세(딥링크 유발 가능) URL 스킵, 언론사 원문만 채택
      if (href.contains('news.naver.com')) continue;
      if (!href.startsWith('http')) continue;
      if (!seenUrl.add(href)) continue;

      items.add(StockNews(
        title: title,
        source: _extractSource(html, href),
        url: href,
        dateKst: _extractDate(html, href),
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

  String _extractSource(String html, String url) {
    final idx = html.indexOf(url);
    if (idx < 0) return '';
    final end = idx + 2000 < html.length ? idx + 2000 : html.length;
    final window = html.substring(idx, end);
    final m = RegExp(
      r'class="[^"]*(?:info press|press|info_press)[^"]*"[^>]*>([^<]+)<',
    ).firstMatch(window);
    return m == null ? '' : _decodeHtml(_stripTags(m.group(1)!).trim());
  }

  DateTime? _extractDate(String html, String url) {
    final idx = html.indexOf(url);
    if (idx < 0) return null;
    final end = idx + 2000 < html.length ? idx + 2000 : html.length;
    final window = html.substring(idx, end);
    // 상대 표기: "3분 전", "5시간 전", "1일 전"
    final rel = RegExp(r'(\d+)\s*(분|시간|일)\s*전').firstMatch(window);
    if (rel != null) {
      final n = int.parse(rel.group(1)!);
      final unit = rel.group(2)!;
      final now = DateTime.now();
      switch (unit) {
        case '분':
          return now.subtract(Duration(minutes: n));
        case '시간':
          return now.subtract(Duration(hours: n));
        case '일':
          return now.subtract(Duration(days: n));
      }
    }
    // 절대 표기: 2026.07.20.
    final abs = RegExp(r'(\d{4})\.(\d{2})\.(\d{2})\.').firstMatch(window);
    if (abs != null) {
      return DateTime(
        int.parse(abs.group(1)!),
        int.parse(abs.group(2)!),
        int.parse(abs.group(3)!),
      );
    }
    return null;
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
        .where(
            (n) => n.dateKst != null && now.difference(n.dateKst!).inHours <= 24)
        .length;
    final total = items.length;
    final kw =
        keywords.isEmpty ? '' : ' · 키워드: ${keywords.take(3).join(", ")}';
    return '최근 뉴스 $total건 (24시간 이내 $recent건)$kw';
  }
}
