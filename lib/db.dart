import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'models.dart';

/// 폰 내부 SQLite (sqflite) 저장소.
/// - watchlist: 사용자가 추가한 종목
/// - prices: 시계열 스냅샷 (PRIMARY KEY: ts_kst + code)
class AppDb {
  AppDb._();
  static final AppDb instance = AppDb._();
  Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'stock_data.db');
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, v) async {
        await db.execute('''
          CREATE TABLE watchlist (
            code TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            added_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE prices (
            ts_kst      TEXT    NOT NULL,
            code        TEXT    NOT NULL,
            name        TEXT    NOT NULL,
            price       INTEGER NOT NULL,
            change      INTEGER,
            change_pct  REAL,
            volume      INTEGER,
            PRIMARY KEY (ts_kst, code)
          )
        ''');
        await db.execute(
            'CREATE INDEX idx_prices_code_ts ON prices(code, ts_kst)');

        // 초기 시드 (사용자가 처음 앱을 켰을 때 빈 화면 방지)
        await _seed(db);
      },
    );
    return _db!;
  }

  Future<void> _seed(Database db) async {
    final now = DateTime.now().toIso8601String();
    for (final t in const [
      Ticker(code: '005930', name: '삼성전자'),
      Ticker(code: '000660', name: 'SK하이닉스'),
      Ticker(code: '035720', name: '카카오'),
    ]) {
      await db.insert('watchlist', {
        'code': t.code,
        'name': t.name,
        'added_at': now,
      });
    }
  }

  // ───── watchlist ─────
  Future<List<Ticker>> listWatchlist() async {
    final rows = await (await db).query('watchlist', orderBy: 'added_at ASC');
    return rows
        .map((r) => Ticker(code: r['code'] as String, name: r['name'] as String))
        .toList();
  }

  Future<void> addWatch(Ticker t) async {
    await (await db).insert(
      'watchlist',
      {
        'code': t.code,
        'name': t.name,
        'added_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> removeWatch(String code) async {
    await (await db).delete('watchlist', where: 'code = ?', whereArgs: [code]);
    await (await db).delete('prices', where: 'code = ?', whereArgs: [code]);
  }

  // ───── prices ─────
  Future<void> insertPrice(PricePoint p) async {
    await (await db).insert(
      'prices',
      p.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<PricePoint?> latestPrice(String code) async {
    final rows = await (await db).query(
      'prices',
      where: 'code = ?',
      whereArgs: [code],
      orderBy: 'ts_kst DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return PricePoint.fromMap(rows.first);
  }

  Future<List<PricePoint>> history(String code, {int limit = 240}) async {
    final rows = await (await db).query(
      'prices',
      where: 'code = ?',
      whereArgs: [code],
      orderBy: 'ts_kst DESC',
      limit: limit,
    );
    final list = rows.map(PricePoint.fromMap).toList();
    return list.reversed.toList();
  }
}
