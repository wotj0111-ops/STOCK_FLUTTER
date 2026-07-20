import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'background_tasks.dart';
import 'db.dart';
import 'detail_page.dart';
import 'models.dart';
import 'scraper.dart';
import 'stock_catalog.dart';

class TickerListPage extends StatefulWidget {
  const TickerListPage({super.key});

  @override
  State<TickerListPage> createState() => _TickerListPageState();
}

class _TickerListPageState extends State<TickerListPage>
    with WidgetsBindingObserver {
  final _db = AppDb.instance;
  final _scraper = NaverFinanceScraper();
  final _won = NumberFormat('#,###');

  List<Ticker> _tickers = [];
  final Map<String, PricePoint> _prices = {};
  Timer? _pollTimer;
  bool _loading = true;

  static const _pollInterval = Duration(seconds: 10);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reload();
    _startPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopPolling();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startPolling();
    } else {
      _stopPolling();
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollOnce();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _pollOnce());
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _reload() async {
    final list = await _db.listWatchlist();
    setState(() {
      _tickers = list;
      _loading = false;
    });
    _pollOnce();
  }

  Future<void> _pollOnce() async {
    for (final t in _tickers) {
      try {
        final p = await _scraper.fetchOne(t);
        if (p == null) continue;
        await _db.insertPrice(p);
        if (t.alertEnabled &&
            !t.alertTriggered &&
            shouldTriggerAlert(ticker: t, currentPrice: p.price)) {
          await sendLocalAlert(ticker: t, currentPrice: p.price);
          await _db.markAlertTriggered(t.code, true);
        }
        if (mounted) setState(() => _prices[t.code] = p);
      } catch (_) {}
    }
  }

  Future<void> _openAddDialog() async {
    final added = await showDialog<Ticker>(
      context: context,
      builder: (_) => _AddTickerDialog(scraper: _scraper),
    );
    if (added != null) {
      await _db.addWatch(added);
      await _reload();
    }
  }

  Future<void> _confirmRemove(Ticker t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('종목 삭제'),
        content: Text('${t.name}(${t.code}) 을(를) 삭제하시겠어요?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('삭제')),
        ],
      ),
    );
    if (ok == true) {
      await _db.removeWatch(t.code);
      await _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('내 주식'),
        centerTitle: false,
        actions: [
          IconButton(
              onPressed: _pollOnce,
              tooltip: '지금 갱신',
              icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddDialog,
        icon: const Icon(Icons.add),
        label: const Text('종목 추가'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _tickers.isEmpty
              ? _emptyState(theme)
              : RefreshIndicator(
                  onRefresh: _pollOnce,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                    itemCount: _tickers.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _tickerCard(_tickers[i]),
                  ),
                ),
    );
  }

  Widget _emptyState(ThemeData theme) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.trending_up, size: 64, color: theme.disabledColor),
            const SizedBox(height: 12),
            Text('등록된 종목이 없습니다', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('아래 + 버튼으로 관심 종목을 추가해 보세요.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.hintColor)),
          ],
        ),
      );

  Widget _tickerCard(Ticker t) {
    final theme = Theme.of(context);
    final p = _prices[t.code];
    final isUp = (p?.change ?? 0) > 0;
    final isDown = (p?.change ?? 0) < 0;
    final priceColor = isUp
        ? Colors.red.shade600
        : isDown
            ? Colors.blue.shade600
            : theme.colorScheme.onSurface;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.dividerColor.withOpacity(0.6)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => DetailPage(ticker: t)),
          );
          _reload();
        },
        onLongPress: () => _confirmRemove(t),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Text(t.name.characters.first,
                    style: TextStyle(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(
                          child: Text(t.name,
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis)),
                      const SizedBox(width: 6),
                      Text(t.code,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.hintColor)),
                    ]),
                    const SizedBox(height: 4),
                    if (t.alertEnabled && t.alertPrice != null)
                      _alertBadge(t)
                    else
                      Text('알림 미설정',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.hintColor)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(p == null ? '-' : '${_won.format(p.price)}원',
                      style: theme.textTheme.titleMedium?.copyWith(
                          color: priceColor, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(
                      p == null
                          ? ''
                          : '${p.change >= 0 ? '+' : ''}${_won.format(p.change)}'
                              ' (${p.changePct.toStringAsFixed(2)}%)',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: priceColor)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _alertBadge(Ticker t) {
    final isAbove = t.alertDirection == AlertDirection.above;
    final color = isAbove ? Colors.red.shade600 : Colors.blue.shade600;
    final icon = isAbove ? Icons.arrow_upward : Icons.arrow_downward;
    final label = isAbove ? '상승 알림' : '하락 알림';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text('$label · ${_won.format(t.alertPrice)}원',
              style: TextStyle(color: color, fontSize: 12)),
          if (t.alertTriggered) ...[
            const SizedBox(width: 4),
            Icon(Icons.check_circle, size: 12, color: color),
          ],
        ],
      ),
    );
  }
}

/// 종목 추가 다이얼로그 — 100% 로컬 검색 + KRX 수동 갱신 버튼
class _AddTickerDialog extends StatefulWidget {
  final NaverFinanceScraper scraper;
  const _AddTickerDialog({required this.scraper});
  @override
  State<_AddTickerDialog> createState() => _AddTickerDialogState();
}

class _AddTickerDialogState extends State<_AddTickerDialog> {
  final _ctl = TextEditingController();
  Timer? _debounce;
  List<Ticker> _results = [];
  bool _searching = false;
  DateTime? _lastRefreshed;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _loadLastRefreshed();
  }

  Future<void> _loadLastRefreshed() async {
    final t = await StockCatalog.instance.lastRefreshed();
    if (!mounted) return;
    setState(() => _lastRefreshed = t);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () async {
      final q = v.trim();
      if (q.isEmpty) {
        setState(() => _results = []);
        return;
      }
      setState(() => _searching = true);
      final list = await widget.scraper.smartSearch(q);
      if (!mounted) return;
      setState(() {
        _results = list;
        _searching = false;
      });
    });
  }

  Future<void> _refreshCatalog() async {
    setState(() => _refreshing = true);
    final ok = await StockCatalog.instance.refreshNow();
    if (!mounted) return;
    setState(() => _refreshing = false);
    await _loadLastRefreshed();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content:
              Text(ok ? '종목 목록을 최신으로 갱신했습니다.' : '갱신에 실패했습니다.')),
    );
    if (_ctl.text.isNotEmpty) _onChanged(_ctl.text);
  }

  String _refreshLabel() {
    if (_refreshing) return '갱신 중...';
    if (_lastRefreshed == null) return '종목 목록 갱신 (KRX)';
    final f = DateFormat('MM/dd HH:mm');
    return '마지막 갱신: ${f.format(_lastRefreshed!)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('종목 추가'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _ctl,
              autofocus: true,
              onChanged: _onChanged,
              decoration: const InputDecoration(
                labelText: '종목명 또는 6자리 코드',
                hintText: '부분일치 지원 · 예) 삼성, 카카오, 005930',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                    child: Text(_refreshLabel(),
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.hintColor))),
                TextButton.icon(
                  onPressed: _refreshing ? null : _refreshCatalog,
                  icon: const Icon(Icons.sync, size: 18),
                  label: const Text('갱신'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 260,
              child: _searching
                  ? const Center(child: CircularProgressIndicator())
                  : _results.isEmpty
                      ? Center(
                          child: Text(
                              _ctl.text.isEmpty
                                  ? '검색어를 입력하세요.'
                                  : '검색 결과가 없습니다.',
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(color: theme.hintColor)),
                        )
                      : ListView.separated(
                          itemCount: _results.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final t = _results[i];
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.trending_up),
                              title: Text(t.name),
                              subtitle: Text(t.code),
                              onTap: () => Navigator.pop(context, t),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소')),
      ],
    );
  }
}
