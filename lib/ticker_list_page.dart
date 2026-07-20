import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'alert_logic.dart';
import 'db.dart';
import 'detail_page.dart';
import 'models.dart';
import 'notification_service.dart';
import 'scraper.dart';

/// 관심종목 리스트 화면 (앱 진입점).
/// - 앱이 열려 있는 동안 1분마다 자동 refresh
/// - pull-to-refresh 지원
/// - + 버튼으로 관심종목 추가 (종목코드 6자리 입력 → 이름 자동 조회)
/// - 알림 조건 충족 시 로컬 알림 발송
class TickerListPage extends StatefulWidget {
  const TickerListPage({super.key});

  @override
  State<TickerListPage> createState() => _TickerListPageState();
}

class _TickerListPageState extends State<TickerListPage> {
  final _fmt = NumberFormat('#,##0');
  final _scraper = NaverFinanceScraper();

  List<_Row> _rows = [];
  bool _loading = true;
  bool _refreshing = false;
  Timer? _timer;
  String? _errorBanner;

  @override
  void initState() {
    super.initState();
    _bootstrap();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final watchlist = await AppDb.instance.listWatchlist();
    final rows = <_Row>[];
    for (final t in watchlist) {
      final latest = await AppDb.instance.latestPrice(t.code);
      rows.add(_Row(ticker: t, price: latest));
    }
    setState(() {
      _rows = rows;
      _loading = false;
    });
    await _refresh();
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
      _errorBanner = null;
    });

    int okCount = 0;
    final failed = <String>[];
    final watchlist = await AppDb.instance.listWatchlist();
    final newRows = <_Row>[];

    for (final t in watchlist) {
      final previous = await AppDb.instance.latestPrice(t.code);
      final p = await _scraper.fetchOne(t);
      if (p != null) {
        await AppDb.instance.insertPrice(p);

        if (shouldTriggerAlert(
          ticker: t,
          currentPrice: p.price,
          previousPrice: previous?.price,
        )) {
          await NotificationService.instance.showTargetReached(
            ticker: t,
            price: p,
          );
          await AppDb.instance.markAlertTriggered(t.code, true);
        }

        final latestTicker = await AppDb.instance.getTicker(t.code) ?? t;
        newRows.add(_Row(ticker: latestTicker, price: p));
        okCount++;
      } else {
        final cached = previous;
        newRows.add(_Row(ticker: t, price: cached));
        failed.add(t.code);
      }
    }

    if (!mounted) return;
    setState(() {
      _rows = newRows;
      _refreshing = false;
      _errorBanner = failed.isEmpty
          ? null
          : (okCount == 0
              ? '네트워크 오류 — 인터넷 연결을 확인하세요.'
              : '일부 종목 조회 실패: ${failed.join(", ")}');
    });
  }

  Future<void> _openAddDialog() async {
    final codeCtrl = TextEditingController();
    String? previewName;
    String? errorText;
    bool loading = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
        Future<void> lookup() async {
          final code = codeCtrl.text.trim();
          if (!RegExp(r'^\d{6}$').hasMatch(code)) {
            setSt(() {
              previewName = null;
              errorText = '종목코드는 숫자 6자리 (예: 005930)';
            });
            return;
          }
          setSt(() {
            loading = true;
            errorText = null;
            previewName = null;
          });
          final name = await _scraper.lookupName(code);
          setSt(() {
            loading = false;
            previewName = name;
            if (name == null) errorText = '해당 종목을 찾을 수 없습니다.';
          });
        }

        Future<void> save() async {
          final code = codeCtrl.text.trim();
          if (previewName == null) {
            await lookup();
            return;
          }
          await AppDb.instance.addWatch(Ticker(code: code, name: previewName!));
          if (!mounted) return;
          Navigator.pop(ctx);
          await _bootstrap();
        }

        return AlertDialog(
          title: const Text('관심종목 추가'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: codeCtrl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: InputDecoration(
                  labelText: '종목코드 (6자리)',
                  hintText: '예: 005930',
                  errorText: errorText,
                  suffixIcon: loading
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : IconButton(
                          icon: const Icon(Icons.search),
                          onPressed: lookup,
                        ),
                ),
                onSubmitted: (_) => lookup(),
              ),
              if (previewName != null) ...[
                const SizedBox(height: 8),
                Text('→ $previewName',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('취소'),
            ),
            FilledButton(onPressed: save, child: const Text('추가')),
          ],
        );
      }),
    );
  }

  Future<void> _confirmDelete(Ticker t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${t.name} 삭제'),
        content: const Text('관심종목에서 제거하고 저장된 시계열 데이터도 삭제합니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await AppDb.instance.removeWatch(t.code);
      await _bootstrap();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('내 주식 대시보드'),
        actions: [
          if (_refreshing)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
            )
          else
            IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddDialog,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_errorBanner != null)
                  Container(
                    width: double.infinity,
                    color: Colors.orange.shade100,
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      _errorBanner!,
                      style: TextStyle(color: Colors.orange.shade900),
                    ),
                  ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _refresh,
                    child: _rows.isEmpty
                        ? ListView(
                            children: const [
                              SizedBox(height: 120),
                              Center(
                                child: Text(
                                  '오른쪽 하단 + 버튼으로\n관심종목을 추가하세요.',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          )
                        : ListView.separated(
                            itemCount: _rows.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (_, i) => _tile(_rows[i]),
                          ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _tile(_Row r) {
    final p = r.price;
    final positive = (p?.change ?? 0) > 0;
    final negative = (p?.change ?? 0) < 0;
    final color = positive ? Colors.red : (negative ? Colors.blue : Colors.grey);

    return Dismissible(
      key: ValueKey('tk-${r.ticker.code}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        await _confirmDelete(r.ticker);
        return false;
      },
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: ListTile(
        title: Row(
          children: [
            Expanded(
              child: Text(
                r.ticker.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (r.ticker.alertEnabled)
              Icon(
                r.ticker.alertTriggered ? Icons.notifications_active : Icons.notifications,
                size: 18,
                color: r.ticker.alertTriggered ? Colors.orange : Colors.indigo,
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(r.ticker.code),
            if (r.ticker.avgPrice != null || r.ticker.alertPrice != null)
              Text(
                '평단 ${formattedWon(r.ticker.avgPrice)} · 목표 ${formattedWon(r.ticker.alertPrice)}',
                style: const TextStyle(fontSize: 12),
              ),
          ],
        ),
        trailing: p == null
            ? const Text('N/A')
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${_fmt.format(p.price)}원',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '${p.change >= 0 ? '+' : ''}${_fmt.format(p.change)} '
                    '(${p.changePct.toStringAsFixed(2)}%)',
                    style: TextStyle(color: color, fontSize: 12),
                  ),
                ],
              ),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => DetailPage(ticker: r.ticker)),
          );
          await _bootstrap();
        },
      ),
    );
  }
}

class _Row {
  final Ticker ticker;
  final PricePoint? price;
  _Row({required this.ticker, required this.price});
}
