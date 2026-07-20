/// 알림 방향: 목표가 이상으로 오르면 알림 / 목표가 이하로 떨어지면 알림
enum AlertDirection { above, below }

/// 감시 대상 종목 (사용자가 추가/삭제 + 알림 설정).
class Ticker {
  final String code;
  final String name;
  final int? avgPrice;
  final int? alertPrice;
  final bool alertEnabled;
  final bool alertTriggered;
  final AlertDirection alertDirection;

  const Ticker({
    required this.code,
    required this.name,
    this.avgPrice,
    this.alertPrice,
    this.alertEnabled = false,
    this.alertTriggered = false,
    this.alertDirection = AlertDirection.above,
  });

  Ticker copyWith({
    String? code,
    String? name,
    int? avgPrice,
    int? alertPrice,
    bool? alertEnabled,
    bool? alertTriggered,
    AlertDirection? alertDirection,
    bool clearAvgPrice = false,
    bool clearAlertPrice = false,
  }) {
    return Ticker(
      code: code ?? this.code,
      name: name ?? this.name,
      avgPrice: clearAvgPrice ? null : (avgPrice ?? this.avgPrice),
      alertPrice: clearAlertPrice ? null : (alertPrice ?? this.alertPrice),
      alertEnabled: alertEnabled ?? this.alertEnabled,
      alertTriggered: alertTriggered ?? this.alertTriggered,
      alertDirection: alertDirection ?? this.alertDirection,
    );
  }

  Map<String, Object?> toMap() => {
        'code': code,
        'name': name,
        'avg_price': avgPrice,
        'alert_price': alertPrice,
        'alert_enabled': alertEnabled ? 1 : 0,
        'alert_triggered': alertTriggered ? 1 : 0,
        'alert_direction':
            alertDirection == AlertDirection.above ? 'above' : 'below',
      };

  factory Ticker.fromMap(Map<String, Object?> m) => Ticker(
        code: m['code'] as String,
        name: m['name'] as String,
        avgPrice: (m['avg_price'] as num?)?.toInt(),
        alertPrice: (m['alert_price'] as num?)?.toInt(),
        alertEnabled: ((m['alert_enabled'] as num?)?.toInt() ?? 0) == 1,
        alertTriggered: ((m['alert_triggered'] as num?)?.toInt() ?? 0) == 1,
        alertDirection: (m['alert_direction'] as String?) == 'below'
            ? AlertDirection.below
            : AlertDirection.above,
      );
}

/// 특정 시각의 시세 스냅샷.
class PricePoint {
  final DateTime tsKst;
  final String code;
  final String name;
  final int price;
  final int change;
  final double changePct;
  final int? volume;

  const PricePoint({
    required this.tsKst,
    required this.code,
    required this.name,
    required this.price,
    required this.change,
    required this.changePct,
    required this.volume,
  });

  Map<String, Object?> toMap() => {
        'ts_kst': tsKst.toIso8601String(),
        'code': code,
        'name': name,
        'price': price,
        'change': change,
        'change_pct': changePct,
        'volume': volume,
      };

  factory PricePoint.fromMap(Map<String, Object?> m) => PricePoint(
        tsKst: DateTime.parse(m['ts_kst'] as String),
        code: m['code'] as String,
        name: m['name'] as String,
        price: (m['price'] as num).toInt(),
        change: (m['change'] as num?)?.toInt() ?? 0,
        changePct: (m['change_pct'] as num?)?.toDouble() ?? 0.0,
        volume: (m['volume'] as num?)?.toInt(),
      );
}
