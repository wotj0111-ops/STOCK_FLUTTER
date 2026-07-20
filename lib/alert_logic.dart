import 'models.dart';

/// 알림 도달 판단 로직.
///
/// - alertPrice >= avgPrice 이면 '익절/상향 도달' 알림
///   → 이전 가격 < 목표가 && 현재 가격 >= 목표가 일 때 트리거
/// - alertPrice < avgPrice 이면 '손절/하향 도달' 알림
///   → 이전 가격 > 목표가 && 현재 가격 <= 목표가 일 때 트리거
/// - previousPrice 가 없으면, 앱이 현재 처음 확인한 시점에 이미 목표 조건을 만족하면 트리거
bool shouldTriggerAlert({
  required Ticker ticker,
  required int currentPrice,
  int? previousPrice,
}) {
  if (!ticker.alertEnabled) return false;
  if (ticker.alertTriggered) return false;
  if (ticker.avgPrice == null || ticker.alertPrice == null) return false;

  final avg = ticker.avgPrice!;
  final target = ticker.alertPrice!;
  final upward = target >= avg;

  if (previousPrice == null) {
    return upward ? currentPrice >= target : currentPrice <= target;
  }

  return upward
      ? (previousPrice < target && currentPrice >= target)
      : (previousPrice > target && currentPrice <= target);
}

String alertModeText(Ticker ticker) {
  if (ticker.avgPrice == null || ticker.alertPrice == null) return '미설정';
  return ticker.alertPrice! >= ticker.avgPrice! ? '익절 알림' : '손절 알림';
}

String formattedWon(int? value) {
  if (value == null) return '-';
  final s = value.toString();
  final chars = s.split('').reversed.toList();
  final out = <String>[];
  for (var i = 0; i < chars.length; i++) {
    if (i > 0 && i % 3 == 0) out.add(',');
    out.add(chars[i]);
  }
  return '${out.reversed.join()}원';
}

String profitText({required int currentPrice, required int avgPrice}) {
  final diff = currentPrice - avgPrice;
  final pct = avgPrice == 0 ? 0.0 : (diff / avgPrice * 100);
  final sign = diff > 0 ? '+' : '';
  return '$sign${formattedWon(diff).replaceAll('원', '')} (${pct.toStringAsFixed(2)}%)';
}
