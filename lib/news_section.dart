import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'news_service.dart';
import 'read_history_store.dart';

class NewsSection extends StatefulWidget {
  final String code;
  final String name;
  const NewsSection({super.key, required this.code, required this.name});

  @override
  State<NewsSection> createState() => _NewsSectionState();
}

class _NewsSectionState extends State<NewsSection> {
  final _svc = StockNewsService();
  final _store = ReadHistoryStore.instance;

  NewsSummary? _summary;
  Set<String> _readUrls = <String>{};
  String? _keywordFilter;
  bool _hideRead = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _svc.fetch(widget.name),
        _store.allRead(),
      ]);
      if (!mounted) return;
      setState(() {
        _summary = results[0] as NewsSummary;
        _readUrls = results[1] as Set<String>;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = '뉴스를 불러오지 못했습니다.';
        _loading = false;
      });
    }
  }

  Future<void> _openUrl(StockNews n) async {
    final uri = Uri.tryParse(n.url);
    if (uri == null) return;

    // 1차: 인앱 브라우저 (WebView) — 네이버 증권 앱 딥링크 회피
    bool ok = false;
    try {
      ok = await launchUrl(
        uri,
        mode: LaunchMode.inAppBrowserView,
      );
    } catch (_) {
      ok = false;
    }

    // 2차: 실패하면 외부 브라우저(크롬 등)
    if (!ok) {
      try {
        ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        ok = false;
      }
    }

    if (ok) {
      await _store.markRead(n.url);
      if (!mounted) return;
      setState(() => _readUrls = {..._readUrls, n.url});
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('링크를 열 수 없습니다.')),
      );
    }
  }

  Future<void> _clearHistory() async {
    await _store.clear();
    if (!mounted) return;
    setState(() => _readUrls = <String>{});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('읽은 뉴스 이력을 초기화했습니다.')),
    );
  }

  List<StockNews> get _visibleItems {
    final items = _summary?.items ?? const <StockNews>[];
    return items.where((n) {
      if (_hideRead && _readUrls.contains(n.url)) return false;
      if (_keywordFilter != null && !n.title.contains(_keywordFilter!)) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: theme.dividerColor.withOpacity(0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(theme),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _errorBox(theme)
            else ...[
              _summaryBox(theme),
              const SizedBox(height: 10),
              _filterBar(theme),
              const SizedBox(height: 4),
              if (_visibleItems.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Text(
                      _hideRead || _keywordFilter != null
                          ? '조건에 맞는 뉴스가 없습니다.'
                          : '최근 뉴스가 없습니다.',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.hintColor),
                    ),
                  ),
                )
              else
                ..._visibleItems.map((n) => _newsTile(theme, n)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _header(ThemeData theme) {
    return Row(
      children: [
        Icon(Icons.article_outlined, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text('관련 뉴스',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        const Spacer(),
        IconButton(
          onPressed: _load,
          tooltip: '새로고침',
          icon: const Icon(Icons.refresh),
        ),
        PopupMenuButton<String>(
          tooltip: '더보기',
          icon: const Icon(Icons.more_vert),
          onSelected: (v) {
            if (v == 'hide_read') {
              setState(() => _hideRead = !_hideRead);
            } else if (v == 'clear_history') {
              _clearHistory();
            } else if (v == 'clear_filter') {
              setState(() => _keywordFilter = null);
            }
          },
          itemBuilder: (_) => [
            CheckedPopupMenuItem<String>(
              value: 'hide_read',
              checked: _hideRead,
              child: const Text('읽은 뉴스 숨기기'),
            ),
            if (_keywordFilter != null)
              const PopupMenuItem<String>(
                value: 'clear_filter',
                child: Text('키워드 필터 해제'),
              ),
            const PopupMenuItem<String>(
              value: 'clear_history',
              child: Text('읽은 이력 초기화'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _errorBox(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_error ?? '',
                style: TextStyle(color: theme.colorScheme.error)),
          ),
          TextButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('재시도'),
          ),
        ],
      ),
    );
  }

  Widget _summaryBox(ThemeData theme) {
    final s = _summary!;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withOpacity(0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.headline,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _filterBar(ThemeData theme) {
    final s = _summary!;
    if (s.keywords.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          ChoiceChip(
            label: const Text('전체'),
            selected: _keywordFilter == null,
            onSelected: (_) => setState(() => _keywordFilter = null),
          ),
          const SizedBox(width: 6),
          for (final k in s.keywords) ...[
            ChoiceChip(
              label: Text('#$k'),
              selected: _keywordFilter == k,
              onSelected: (_) => setState(() {
                _keywordFilter = _keywordFilter == k ? null : k;
              }),
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }

  Widget _newsTile(ThemeData theme, StockNews n) {
    final df = DateFormat('MM/dd HH:mm');
    final date = n.dateKst == null ? '' : df.format(n.dateKst!);
    final isRead = _readUrls.contains(n.url);
    final isNew = n.dateKst != null &&
        DateTime.now().difference(n.dateKst!).inHours <= 24;

    final titleStyle = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w600,
      color: isRead ? theme.hintColor : theme.colorScheme.onSurface,
      decoration: isRead ? TextDecoration.lineThrough : null,
      decorationColor: theme.hintColor,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openUrl(n),
          onLongPress: () async {
            if (isRead) return;
            await _store.markRead(n.url);
            if (!mounted) return;
            setState(() => _readUrls = {..._readUrls, n.url});
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('읽음으로 표시했습니다.')),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: isRead
                  ? theme.colorScheme.surfaceContainerHighest.withOpacity(0.3)
                  : null,
              border: Border(
                left: BorderSide(
                  width: 3,
                  color: isNew
                      ? Colors.red.shade400
                      : theme.dividerColor.withOpacity(0.5),
                ),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (isNew) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text('NEW',
                                  style: TextStyle(
                                    color: Colors.red.shade600,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  )),
                            ),
                            const SizedBox(width: 6),
                          ],
                          if (isRead) ...[
                            Icon(Icons.check_circle,
                                size: 14, color: theme.hintColor),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Text(n.title,
                                style: titleStyle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [n.source, if (date.isNotEmpty) date]
                            .where((e) => e.isNotEmpty)
                            .join(' · '),
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.hintColor),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.open_in_new, size: 18, color: theme.hintColor),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
