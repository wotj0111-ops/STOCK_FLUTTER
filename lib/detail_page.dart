import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'background_tasks.dart';
import 'db.dart';
import 'models.dart';
import 'news_section.dart';
import 'scraper.dart';

class DetailPage extends StatefulWidget {
  final Ticker ticker;
  const DetailPage({super.key, required this.ticker});

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> with WidgetsBindingObserver {
  final _db = AppDb.instance;
  final _scraper = NaverFinanceScraper();
  final _won = NumberFormat('#,###');

  late TextEditingController _avgCtl;
  late TextEditingController _alertCtl;

  Ticker _t = const Ticker(code: '', name: '');
  PricePoint? _price;
  AlertDirection _direction = AlertDirection.above;
  bool _enabled = false;

  Timer? _pollTimer;
  static const _pollInterval = Duration(seconds: 10);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _t = widget.ticker;
    _direction = _t.alertDirection;
    _enabled = _t.alertEnabled;
    _avgCtl = TextEditingController(text: _t.avgPrice?.toString() ?? '');
    _alertCtl = TextEditingController(text: _t.alertPrice?.toString() ?? '');
    _startPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopPolling();
    _avgCtl.dispose();
    _alertCtl.dispose();
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

  Future<void> _pollOnce() async {
    try {
      final p = await _scraper.fetchOne(_t);
      if (p == null) return;
      await _db.insertPrice(p);
      if (!mounted) return;
      setState(() => _price = p);
    } catch (_) {}
  }

  Future<void> _save() async {
    final alertText = _alertCtl.text.trim();
    if (_enabled && alertText.isEmpty) {
      _snack('알림 가격을 입력해 주세요.');
      return;
    }
    final alertPrice = alertText.isEmpty ? null : int.tryParse(alertText);
    final avgPrice =
        _avgCtl.text.trim().isEmpty ? null : int.tryParse(_avgCtl.text.trim());

    if (_enabled && alertPrice == null) {
      _snack('알림 가격은 숫자만 입력 가능합니다.');
      return;
    }

    await _db.updateAlertSettings(
      code: _t.code,
      avgPrice: avgPrice,
      alertPrice: alertPrice,
      alertEnabled: _enabled,
      alertDirection: _direction,
    );
    final updated = await _db.getTicker(_t.code);
    if (!mounted) return;
    setState(() => _t = updated ?? _t);
    _snack('알림 설정이 저장되었습니다.');
  }

  Future<void> _reset() async {
    await _db.updateAlertSettings(
      code: _t.code,
      avgPrice: null,
      alertPrice: null,
      alertEnabled: false,
      alertDirection: AlertDirection.above,
    );
    if (!mounted) return;
    setState(() {
      _enabled = false;
      _direction = AlertDirection.above;
      _avgCtl.clear();
      _alertCtl.clear();
    });
    _snack('알림 설정이 초기화되었습니다.');
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_t.name),
        actions: [
          IconButton(
            onPressed: _pollOnce,
            tooltip: '지금 갱신',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _priceCard(theme),
          const SizedBox(height: 16),
          _alertCard(theme),
          const SizedBox(height: 16),
          NewsSection(code: _t.code),
        ],
      ),
    );
  }

  Widget _priceCard(ThemeData theme) {
    final p = _price;
    final isUp = (p?.change ?? 0) > 0;
    final isDown = (p?.change ?? 0) < 0;
    final color = isUp
        ? Colors.red.shade600
        : isDown
            ? Colors.blue.shade600
            : theme.colorScheme.onSurface;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primaryContainer.withOpacity(0.4),
            theme.colorScheme.primaryContainer.withOpacity(0.1),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(_t.name,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Text(_t.code,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.hintColor)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                          shape: BoxShape.circle, color: Colors.green),
                    ),
                    const SizedBox(width: 4),
                    const Text('실시간', style: TextStyle(fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            p == null ? '-' : '${_won.format(p.price)}원',
            style: theme.textTheme.displaySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            p == null
                ? '데이터를 불러오는 중...'
                : '${p.change >= 0 ? '+' : ''}${_won.format(p.change)}'
                    '  (${p.changePct.toStringAsFixed(2)}%)',
            style: theme.textTheme.titleMedium?.copyWith(color: color),
          ),
          if (p != null) ...[
            const SizedBox(height: 12),
            Text(
              '거래량: ${p.volume == null ? '-' : _won.format(p.volume)}',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            ),
            Text(
              '업데이트: ${DateFormat('HH:mm:ss').format(p.tsKst)}',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            ),
          ],
        ],
      ),
    );
  }

  Widget _alertCard(ThemeData theme) {
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
            Row(
              children: [
                Icon(Icons.notifications_active,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('알림 설정',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                Switch(
                  value: _enabled,
                  onChanged: (v) => setState(() => _enabled = v),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _avgCtl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: '평단가 (선택)',
                hintText: '참고용 · 필수 아님',
                prefixIcon: Icon(Icons.savings_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _alertCtl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: '알림 가격',
                hintText: '이 가격에 도달하면 알림',
                prefixIcon: Icon(Icons.price_check),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            Text('알림 조건',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: _directionTile(
                    theme,
                    dir: AlertDirection.above,
                    label: '이 가격 이상으로 오르면',
                    icon: Icons.arrow_upward,
                    color: Colors.red.shade600,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _directionTile(
                    theme,
                    dir: AlertDirection.below,
                    label: '이 가격 이하로 떨어지면',
                    icon: Icons.arrow_downward,
                    color: Colors.blue.shade600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _reset,
                    icon: const Icon(Icons.refresh),
                    label: const Text('초기화'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.check),
                    label: const Text('저장'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _directionTile(
    ThemeData theme, {
    required AlertDirection dir,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    final selected = _direction == dir;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => setState(() => _direction = dir),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(
            color: selected ? color : theme.dividerColor,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
          color: selected ? color.withOpacity(0.06) : null,
        ),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: selected ? color : null)),
            ),
            if (selected) Icon(Icons.check_circle, size: 18, color: color),
          ],
        ),
      ),
    );
  }
}
