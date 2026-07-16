/// 감시 대상 종목 (사용자가 추가/삭제).
class Ticker {
  final String code;
  final String name;
  const Ticker({required this.code, required this.name});

  Map<String, Object?> toMap() => {'code': code, 'name': name};
  factory Ticker.fromMap(Map<String, Object?> m) =>
      Ticker(code: m['code'] as String, name: m['name'] as String);
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
