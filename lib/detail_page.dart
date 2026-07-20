import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'alert_logic.dart';
import 'db.dart';
import 'models.dart';
import 'scraper.dart';

/// 종목 상세 화면.
///
/// 기존 차트/표 중심 화면 대신:
/// - 현재가 요약 카드
/// - 평단가 / 목표가 / 알림 on-off 설정 UI
/// 를 중심으로 재구성한다.
class DetailPage extends StatefulWidget {
  final Ticker ticker;
  const DetailPage({super.key, required this.ticker});

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  final _fmt = NumberFormat('#,##0');
  final _scraper = NaverFinanceScraper();

  final _avgCtrl = TextEditingController();
  final _targetCtrl = TextEditingController();

  Ticker? _ticker;
  PricePoint? _price;
  Timer? _timer;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  bool _alertEnabled = false;

  @override
  void initState() {
    super.initState();
    _ticker = widget.ticker;
    _syncControllers(widget.ticker);
    _refresh();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _avgCtrl.dispose();
    _targetCtrl.dispose();
    super.dispose();
  }

  void _syncControllers(Ticker t) {
    _avgCtrl.text = t.avgPrice?.toString() ?? '';
    _targetCtrl.text = t.alertPrice?.toString() ?? '';
    _alertEnabled = t.alertEnabled;
  }

  Future<void> _refresh() async {
    try {
      final latestTicker = await AppDb.instance.getTicker(widget.ticker.code) ?? widget.ticker;
      final previous = await AppDb.instance.latestPrice(widget.ticker.code);
      final fetched = await _scraper.fetchOne(latestTicker);
      if (fetched != null) {
        await AppDb.instance.insertPrice(fetched);
      }
      final current = fetched ?? previous;
      if (!mounted) return;
      setState(() {
        _ticker = latestTicker;
        _price = current;
        _loading = false;
        _error = current == null ? '데이터를 불러올 수 없습니다. 잠시 후 다시 시도하세요.' : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  int? _parseInt(String text) {
    final cleaned = text.replaceAll(RegExp(r'[^\d]'), '');
    if (cleaned.isEmpty) return null;
    return int.tryParse(cleaned);
  }

  Future<void> _saveAlertSettings() async {
    final avg = _parseInt(_avgCtrl.text);
    final target = _parseInt(_targetCtrl.text);

    if (_alertEnabled && (avg == null || target == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('알림을 켜려면 평단가와 목표가를 모두 입력하세요.')),
      );
      return;
    }

    setState(() => _saving = true);
    await AppDb.instance.updateAlertSettings(
      code: widget.ticker.code,
      avgPrice: avg,
      alertPrice: target,
      alertEnabled: _alertEnabled && avg != null && target != null,
    );

    final updated = await AppDb.instance.getTicker(widget.ticker.code);
    if (!mounted) return;
    setState(() {
      _ticker = updated ?? _ticker;
      _saving = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('알림 설정이 저장되었습니다.')),
    );
  }

  Future<void> _clearAlertSettings() async {
    setState(() => _saving = true);
    await AppDb.instance.updateAlertSettings(
      code: widget.ticker.code,
      avgPrice: null,
      alertPrice: null,
      alertEnabled: false,
    );
    final updated = await AppDb.instance.getTicker(widget.ticker.code);
    if (!mounted) return;
    setState(() {
      _ticker = updated ?? _ticker;
      _syncControllers(_ticker!);
      _saving = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('알림 설정을 초기화했습니다.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ticker = _ticker ?? widget.ticker;
    return Scaffold(
      appBar: AppBar(
        title: Text('${ticker.name} · ${ticker.code}'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null)
                    Card(
                      color: Colors.orange.shade100,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(_error!),
                      ),
                    ),
                  if (_price != null) _headerCard(_price!, ticker),
                  const SizedBox(height: 16),
                  _alertCard(ticker),
                ],
              ),
            ),
    );
  }

  Widget _headerCard(PricePoint p, Ticker ticker) {
    final positive = p.change > 0;
    final negative = p.change < 0;
    final color = positive ? Colors.red : (negative ? Colors.blue : Colors.grey);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(p.name, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              DateFormat('yyyy-MM-dd HH:mm:ss').format(p.tsKst),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${_fmt.format(p.price)}원',
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 12),
                Text(
                  '${p.change >= 0 ? '+' : ''}${_fmt.format(p.change)} '
                  '(${p.changePct.toStringAsFixed(2)}%)',
                  style: TextStyle(color: color, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _infoChip('거래량', p.volume != null ? '${_fmt.format(p.volume)}' : '-'),
                _infoChip('평단가', formattedWon(ticker.avgPrice)),
                _infoChip('목표가', formattedWon(ticker.alertPrice)),
                _infoChip('알림유형', alertModeText(ticker)),
              ],
            ),
            if (ticker.avgPrice != null) ...[
              const SizedBox(height: 12),
              Text(
                '현재 수익률 기준: ${profitText(currentPrice: p.price, avgPrice: ticker.avgPrice!)}',
                style: TextStyle(
                  color: p.price >= ticker.avgPrice! ? Colors.red : Colors.blue,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _alertCard(Ticker ticker) {
    final avg = _parseInt(_avgCtrl.text);
    final target = _parseInt(_targetCtrl.text);
    final mode = (avg != null && target != null)
        ? (target >= avg ? '익절 알림' : '손절 알림')
        : '미설정';
    final price = _price;
    final reached = price != null && avg != null && target != null
        ? (target >= avg ? price.price >= target : price.price <= target)
        : false;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.notifications_active_outlined),
                const SizedBox(width: 8),
                Text('알림 설정', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Switch(
                  value: _alertEnabled,
                  onChanged: (v) => setState(() => _alertEnabled = v),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _avgCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: '나의 평단가',
                hintText: '예: 73500',
                border: OutlineInputBorder(),
                suffixText: '원',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _targetCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: '알람 목표가',
                hintText: '예: 80000',
                border: OutlineInputBorder(),
                suffixText: '원',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('알림 상태: ${_alertEnabled ? 'ON' : 'OFF'}'),
                  const SizedBox(height: 4),
                  Text('알림 유형: $mode'),
                  if (ticker.alertTriggered)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text('이미 한 번 알림이 발송되었습니다. 설정 저장 시 다시 활성화됩니다.'),
                    ),
                  if (reached)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text('현재 가격이 이미 목표 조건에 도달했습니다.'),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : _clearAlertSettings,
                    child: const Text('초기화'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : _saveAlertSettings,
                    child: Text(_saving ? '저장 중...' : '저장'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text('$label  $value'),
    );
  }
}
