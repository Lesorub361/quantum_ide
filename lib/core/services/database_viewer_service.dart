import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

class TableInfo {
  final String name;
  final int rowCount;
  final List<ColumnInfo> columns;

  const TableInfo({
    required this.name,
    required this.rowCount,
    required this.columns,
  });
}

class ColumnInfo {
  final String name;
  final String type;
  final bool isPrimaryKey;
  final bool isNotNull;
  final String? defaultValue;

  const ColumnInfo({
    required this.name,
    required this.type,
    this.isPrimaryKey = false,
    this.isNotNull = false,
    this.defaultValue,
  });
}

class QueryResult {
  final List<String> columns;
  final List<List<dynamic>> rows;
  final int affectedRows;
  final String? error;
  final Duration duration;

  const QueryResult({
    required this.columns,
    required this.rows,
    this.affectedRows = 0,
    this.error,
    required this.duration,
  });

  bool get isSuccess => error == null;
}

class DatabaseViewerState {
  final String? dbPath;
  final List<TableInfo> tables;
  final String? selectedTable;
  final QueryResult? lastResult;
  final bool isLoading;
  final List<String> queryHistory;

  const DatabaseViewerState({
    this.dbPath,
    this.tables = const [],
    this.selectedTable,
    this.lastResult,
    this.isLoading = false,
    this.queryHistory = const [],
  });

  DatabaseViewerState copyWith({
    String? dbPath,
    List<TableInfo>? tables,
    String? selectedTable,
    QueryResult? lastResult,
    bool? isLoading,
    List<String>? queryHistory,
  }) {
    return DatabaseViewerState(
      dbPath: dbPath ?? this.dbPath,
      tables: tables ?? this.tables,
      selectedTable: selectedTable ?? this.selectedTable,
      lastResult: lastResult ?? this.lastResult,
      isLoading: isLoading ?? this.isLoading,
      queryHistory: queryHistory ?? this.queryHistory,
    );
  }
}

class DatabaseViewerService extends StateNotifier<DatabaseViewerState> {
  final Ref ref;
  Database? _db;

  DatabaseViewerService(this.ref) : super(const DatabaseViewerState());

  Future<void> openDatabase(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      state = state.copyWith(isLoading: false);
      return;
    }

    try {
      _db = await databaseFactory.openDatabase(path);
      final tables = await _getTables();
      state = state.copyWith(
        dbPath: path,
        tables: tables,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<List<TableInfo>> _getTables() async {
    if (_db == null) return [];

    try {
      final results = await _db!.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
      );

      final tables = <TableInfo>[];
      for (final row in results) {
        final tableName = row['name'] as String;
        final columns = await _getTableColumns(tableName);
        final countResult = await _db!.rawQuery('SELECT COUNT(*) as cnt FROM "$tableName"');
        final rowCount = countResult.first['cnt'] as int;

        tables.add(TableInfo(
          name: tableName,
          rowCount: rowCount,
          columns: columns,
        ));
      }
      return tables;
    } catch (e) {
      return [];
    }
  }

  Future<List<ColumnInfo>> _getTableColumns(String tableName) async {
    if (_db == null) return [];

    try {
      final results = await _db!.rawQuery('PRAGMA table_info("$tableName")');
      return results.map((row) {
        final pk = row['pk'] as int;
        return ColumnInfo(
          name: row['name'] as String,
          type: row['type'] as String,
          isPrimaryKey: pk > 0,
          isNotNull: (row['notnull'] as int) == 1,
          defaultValue: row['dflt_value'] as String?,
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }

  Future<QueryResult> executeQuery(String sql) async {
    if (_db == null) {
      return const QueryResult(
        columns: [],
        rows: [],
        error: 'No database open',
        duration: Duration.zero,
      );
    }

    final stopwatch = Stopwatch()..start();

    try {
      final upperSql = sql.trim().toUpperCase();
      if (upperSql.startsWith('SELECT') || upperSql.startsWith('PRAGMA') || upperSql.startsWith('EXPLAIN')) {
        final results = await _db!.rawQuery(sql);
        stopwatch.stop();

        final columns = results.isNotEmpty ? results.first.keys.toList() : <String>[];
        final rows = results.map((r) => columns.map((c) => r[c]).toList()).toList();

        final history = List<String>.from(state.queryHistory);
        if (!history.contains(sql)) {
          history.insert(0, sql);
          if (history.length > 50) history.removeLast();
        }
        state = state.copyWith(queryHistory: history);

        return QueryResult(
          columns: columns,
          rows: rows,
          duration: stopwatch.elapsed,
        );
      } else {
        final affected = await _db!.rawUpdate(sql);
        stopwatch.stop();

        final history = List<String>.from(state.queryHistory);
        if (!history.contains(sql)) {
          history.insert(0, sql);
          if (history.length > 50) history.removeLast();
        }
        state = state.copyWith(queryHistory: history);

        return QueryResult(
          columns: [],
          rows: [],
          affectedRows: affected,
          duration: stopwatch.elapsed,
        );
      }
    } catch (e) {
      stopwatch.stop();
      return QueryResult(
        columns: [],
        rows: [],
        error: e.toString(),
        duration: stopwatch.elapsed,
      );
    }
  }

  Future<void> selectTable(String tableName) async {
    state = state.copyWith(selectedTable: tableName);
  }

  String generateSelectQuery(String tableName, {int limit = 100}) {
    return 'SELECT * FROM "$tableName" LIMIT $limit';
  }

  Future<void> refreshTables() async {
    final tables = await _getTables();
    state = state.copyWith(tables: tables);
  }

  void close() {
    _db?.close();
    _db = null;
    state = const DatabaseViewerState();
  }

  @override
  void dispose() {
    _db?.close();
    super.dispose();
  }
}

final databaseViewerProvider = StateNotifierProvider<DatabaseViewerService, DatabaseViewerState>((ref) {
  return DatabaseViewerService(ref);
});
