import 'package:sqflite/sqflite.dart';

/// 每日生成成功统计数据源。操作 daily_generation_stats 表，
/// 独立于 generation_history（会被裁剪），按天累加、长期保留。
/// 日期为本地时区 yyyy-MM-dd，每日 0 点自然重置（新的一天是新行）。
class DailyStatsLocalDatasource {
  final Database _db;

  DailyStatsLocalDatasource(this._db);

  static const String _table = 'daily_generation_stats';

  static String _dateKey(DateTime time) {
    final local = time.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }

  /// 记录一次生成成功（幂等由调用方保证，同一 taskId 不重复计数）。
  Future<void> recordSuccess(DateTime time) async {
    final date = _dateKey(time);
    await _db.rawInsert(
      'INSERT INTO $_table(date, success_count, updated_at) '
      'VALUES(?, 1, ?) '
      'ON CONFLICT(date) DO UPDATE SET '
      'success_count = success_count + 1, updated_at = ?',
      [date, time.millisecondsSinceEpoch, time.millisecondsSinceEpoch],
    );
  }

  /// 某一天的成功数。
  Future<int> getSuccessCount(DateTime time) async {
    final rows = await _db.query(
      _table,
      columns: ['success_count'],
      where: 'date = ?',
      whereArgs: [_dateKey(time)],
      limit: 1,
    );
    if (rows.isEmpty) return 0;
    return (rows.first['success_count'] as int?) ?? 0;
  }

  /// 最近 [days] 天（含今天）的每日成功数，按日期升序。
  Future<Map<String, int>> getRecentCounts({int days = 7}) async {
    final now = DateTime.now().toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final rows = await _db.query(
      _table,
      where: 'date >= ?',
      whereArgs: [_dateKey(today.subtract(Duration(days: days - 1)))],
      orderBy: 'date ASC',
    );
    return {
      for (final row in rows)
        row['date'] as String: (row['success_count'] as int?) ?? 0,
    };
  }
}
