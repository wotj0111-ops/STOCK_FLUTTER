import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'models.dart';

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
      version: 5,
      onCreate: (db, v) async {
        await db.execute('''
          CREATE TABLE watchlist (
            code TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            added_at TEXT NOT NULL,
            avg_price INTEGER,
            alert_price INTEGER,
            alert_enabled INTEGER NOT NULL DEFAULT 0,
            alert_triggered INTEGER NOT NULL DEFAULT 0,
            alert_direction TEXT NOT NULL DEFAULT 'above',
            sort_order INTEGER NOT NULL DEFAULT 0
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
        await db.execute('''
          CREATE TABLE stocks (
            code TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            market TEXT,
            updated_at TEXT NOT NULL
          )
        ''');
        await db.execute('CREATE INDEX idx_stocks_name ON stocks(name)');
        await _seed(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE watchlist ADD COLUMN avg_price INTEGER');
          await db.execute('ALTER TABLE watchlist ADD COLUMN alert_price INTEGER');
          await db.execute(
              'ALTER TABLE watchlist ADD COLUMN alert_enabled INTEGER NOT NULL DEFAULT 0');
          await db.execute(
              'ALTER TABLE watchlist ADD COLUMN alert_triggered INTEGER NOT NULL DEFAULT 0');
        }
        if (oldVersion < 3) {
          await db.execute(
              "ALTER TABLE watchlist ADD COLUMN alert_direction TEXT NOT NULL DEFAULT 'above'");
        }
        if (oldVersion < 4) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS stocks (
              code TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              market TEXT,
              updated_at TEXT NOT NULL
            )
          ''');
          await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_stocks_name ON stocks(name)');
        }
        if (oldVersion < 5) {
          await db.execute(
              'ALTER TABLE watchlist ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0');
          // 기존 데이터에 added_at 기준으로 순번 부여
          final rows = await db.query('watchlist', orderBy: 'added_at ASC');
          for (var i = 0; i < rows.length; i++) {
            await db.update('watchlist', {'sort_order': i},
                where: 'code = ?', whereArgs: [rows[i]['code']]);
          }
        }
      },
    );
    return _db!;
  }

  Future<void> _seed(Database db) async {
    final now = DateTime.now().toIso8601String();
    const seeds = [
      Ticker(code: '005930', name: '삼성전자'),
      Ticker(code: '000660', name: 'SK하이닉스'),
      Ticker(code: '035720', name: '카카오'),
    ];
    for (var i = 0; i < seeds.length; i++) {
      final t = seeds[i];
      await db.insert('watchlist', {
        'code': t.code,
        'name': t.name,
        'added_at': now,
        'avg_price': t.avgPrice,
        'alert_price': t.alertPrice,
        'alert_enabled': t.alertEnabled ? 1 : 0,
        'alert_triggered': t.alertTriggered ? 1 : 0,
        'alert_direction': 'above',
        'sort_order': i,
      });
    }
  }

  Future<List<Ticker>> listWatchlist() async {
    final rows = await (await db)
        .query('watchlist', orderBy: 'sort_order ASC, added_at ASC');
    return rows.map((r) => Ticker.fromMap(r)).toList();
  }

  Future<Ticker?> getTicker(String code) async {
    final rows = await (await db).query('watchlist',
        where: 'code = ?', whereArgs: [code], limit: 1);
    if (rows.isEmpty) return null;
    return Ticker.fromMap(rows.first);
  }

  Future<void> addWatch(Ticker t) async {
    final d = await db;
    // 새 종목은 맨 뒤에
    final maxRow = await d.rawQuery(
        'SELECT COALESCE(MAX(sort_order), -1) + 1 AS next FROM watchlist');
    final next = (maxRow.first['next'] as num?)?.toInt() ?? 0;
    await d.insert(
      'watchlist',
      {
        'code': t.code,
        'name': t.name,
        'added_at': DateTime.now().toIso8601String(),
        'avg_price': t.avgPrice,
        'alert_price': t.alertPrice,
        'alert_enabled': t.alertEnabled ? 1 : 0,
        'alert_triggered': t.alertTriggered ? 1 : 0,
        'alert_direction':
            t.alertDirection == AlertDirection.above ? 'above' : 'below',
        'sort_order': next,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateAlertSettings({
    required String code,
    int? avgPrice,
    int? alertPrice,
    required bool alertEnabled,
    required AlertDirection alertDirection,
  }) async {
    await (await db).update(
      'watchlist',
      {
        'avg_price': avgPrice,
        'alert_price': alertPrice,
        'alert_enabled': alertEnabled ? 1 : 0,
        'alert_triggered': 0,
        'alert_direction':
            alertDirection == AlertDirection.above ? 'above' : 'below',
      },
      where: 'code = ?',
      whereArgs: [code],
    );
  }

  Future<void> markAlertTriggered(String code, bool triggered) async {
    await (await db).update('watchlist',
        {'alert_triggered': triggered ? 1 : 0},
        where: 'code = ?', whereArgs: [code]);
  }

  Future<void> removeWatch(String code) async {
    await (await db).delete('watchlist', where: 'code = ?', whereArgs: [code]);
    await (await db).delete('prices', where: 'code = ?', whereArgs: [code]);
  }

  /// 목록 순서 저장 (드래그 앤 드롭 결과)
  Future<void> reorderWatchlist(List<String> codesInOrder) async {
    final d = await db;
    final batch = d.batch();
    for (var i = 0; i < codesInOrder.length; i++) {
      batch.update('watchlist', {'sort_order': i},
          where: 'code = ?', whereArgs: [codesInOrder[i]]);
    }
    await batch.commit(noResult: true);
  }

  Future<void> insertPrice(PricePoint p) async {
    await (await db).insert('prices', p.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<PricePoint?> latestPrice(String code) async {
    final rows = await (await db).query('prices',
        where: 'code = ?',
        whereArgs: [code],
        orderBy: 'ts_kst DESC',
        limit: 1);
    if (rows.isEmpty) return null;
    return PricePoint.fromMap(rows.first);
  }

  Future<List<PricePoint>> history(String code, {int limit = 240}) async {
    final rows = await (await db).query('prices',
        where: 'code = ?',
        whereArgs: [code],
        orderBy: 'ts_kst DESC',
        limit: limit);
    return rows.map(PricePoint.fromMap).toList().reversed.toList();
  }

  // ─── stocks (카탈로그) ─────
  Future<int> stocksCount() async {
    final r = await (await db).rawQuery('SELECT COUNT(*) c FROM stocks');
    return (r.first['c'] as int?) ?? 0;
  }

  Future<void> bulkUpsertStocks(List<Map<String, Object?>> rows) async {
    final d = await db;
    final now = DateTime.now().toIso8601String();
    final batch = d.batch();
    for (final r in rows) {
      batch.insert(
          'stocks',
          {
            'code': r['code'],
            'name': r['name'],
            'market': r['market'],
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, Object?>>> searchStocks(String q,
      {int limit = 20}) async {
    final d = await db;
    final k = q.trim();
    if (k.isEmpty) return [];
    final like = '%$k%';
    return d.rawQuery('''
      SELECT code, name, market FROM stocks
      WHERE name LIKE ? OR code LIKE ?
      ORDER BY
        CASE
          WHEN name = ? THEN 0
          WHEN name LIKE ? THEN 1
          WHEN name LIKE ? THEN 2
          ELSE 3
        END,
        name ASC
      LIMIT ?
    ''', [like, like, k, '$k%', like, limit]);
  }
}
