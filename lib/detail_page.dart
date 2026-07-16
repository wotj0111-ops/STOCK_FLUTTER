import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import 'db.dart';
import 'models.dart';
import 'scraper.dart';

/// 종목 상세 화면 (헤더 + 미니 라인차트).
class DetailPage extends StatefulWidget {
  final Ticker ticker;
  const DetailPage({super.key, required this.ticker});

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  final _fmt = NumberFormat('#,##0');
  final _scraper = NaverFinanceScraper();

  PricePoint? _price;
  List<PricePoint> _history = [];
  Timer? _timer;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final p = await _scraper.fetchOne(widget.ticker);
      if (p != null) await AppDb.instance.insertPrice(p);
      final cached = p ?? await AppDb.instance.latestPrice(widget.ticker.code);
      final history =
          await AppDb.instance.history(widget.ticker.code, limit: 240);
      if (!mounted) return;
      setState(() {
        _price = cached;
        _history = history;
        _loading = false;
        _error = (p == null && cached == null)
            ? '데이터를 불러올 수 없습니다. 잠시 후 다시 시도하세요.'
            : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.ticker.name} · ${widget.ticker.code}'),
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
                  if (_price != null) _headerCard(_price!),
                  const SizedBox(height: 16),
                  _chartCard(),
                ],
              ),
            ),
    );
  }

  Widget _headerCard(PricePoint p) {
    final positive = p.change > 0;
    final negative = p.change < 0;
    final color =
        positive ? Colors.red : (negative ? Colors.blue : Colors.grey);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(p.name, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(DateFormat('yyyy-MM-dd HH:mm:ss').format(p.tsKst),
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${_fmt.format(p.price)}원',
                    style: const TextStyle(
                        fontSize: 32, fontWeight: FontWeight.bold)),
                const SizedBox(width: 12),
                Text(
                  '${p.change >= 0 ? '+' : ''}${_fmt.format(p.change)} '
                  '(${p.changePct.toStringAsFixed(2)}%)',
                  style: TextStyle(color: color, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('거래량: ${p.volume != null ? _fmt.format(p.volume) : "-"}'),
          ],
        ),
      ),
    );
  }

  Widget _chartCard() {
    if (_history.length < 2) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('시간이 지나면서 데이터가 쌓이면 차트가 그려집니다.\n'
              '(앱을 켜둔 채로 1분마다 자동 수집)'),
        ),
      );
    }
    final spots = <FlSpot>[];
    for (var i = 0; i < _history.length; i++) {
      spots.add(FlSpot(i.toDouble(), _history[i].price.toDouble()));
    }
    final prices = _history.map((e) => e.price).toList();
    final minY = prices.reduce((a, b) => a < b ? a : b).toDouble();
    final maxY = prices.reduce((a, b) => a > b ? a : b).toDouble();
    final pad = (maxY - minY) * 0.05 + 1;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 20, 20, 12),
        child: SizedBox(
          height: 260,
          child: LineChart(
            LineChartData(
              minY: minY - pad,
              maxY: maxY + pad,
              gridData: const FlGridData(show: true),
              titlesData: const FlTitlesData(
                topTitles:
                    AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: false,
                  barWidth: 2,
                  dotData: const FlDotData(show: false),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
