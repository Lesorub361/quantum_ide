import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:quantum_ide/core/services/database_viewer_service.dart';

class DatabaseViewerPage extends ConsumerStatefulWidget {
  const DatabaseViewerPage({super.key});

  @override
  ConsumerState<DatabaseViewerPage> createState() => _DatabaseViewerPageState();
}

class _DatabaseViewerPageState extends ConsumerState<DatabaseViewerPage> {
  final _sqlController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _sqlController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _pickDatabase() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['db', 'sqlite', 'sqlite3'],
    );
    if (result != null && result.files.single.path != null) {
      ref.read(databaseViewerProvider.notifier).openDatabase(result.files.single.path!);
    }
  }

  Future<void> _executeQuery() async {
    final sql = _sqlController.text.trim();
    if (sql.isEmpty) return;
    final result = await ref.read(databaseViewerProvider.notifier).executeQuery(sql);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.isSuccess
              ? 'Query executed in ${result.duration.inMilliseconds}ms'
              : 'Error: ${result.error}'),
          backgroundColor: result.isSuccess ? Colors.green : Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final dbState = ref.watch(databaseViewerProvider);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Row(
        children: [
          _buildSidebar(dbState, colorScheme),
          Expanded(
            child: Column(
              children: [
                _buildToolbar(dbState, colorScheme),
                Expanded(
                  child: dbState.dbPath == null
                      ? _buildEmptyState(colorScheme)
                      : _buildContent(dbState, colorScheme),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar(DatabaseViewerState dbState, ColorScheme colorScheme) {
    final theme = Theme.of(context);
    return Container(
      width: 200,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        border: Border(right: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.database, size: 16, color: colorScheme.primary),
                const SizedBox(width: 6),
                Text('Tables', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          Expanded(
            child: dbState.tables.isEmpty
                ? Center(
                    child: Text(
                      'No tables',
                      style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: dbState.tables.length,
                    itemBuilder: (context, index) {
                      final table = dbState.tables[index];
                      final isSelected = dbState.selectedTable == table.name;
                      return ListTile(
                        dense: true,
                        selected: isSelected,
                        selectedTileColor: colorScheme.primaryContainer.withValues(alpha: 0.3),
                        leading: Icon(LucideIcons.table_2, size: 14, color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant),
                        title: Text(table.name, style: const TextStyle(fontSize: 12)),
                        subtitle: Text('${table.rowCount} rows', style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant)),
                        onTap: () {
                          ref.read(databaseViewerProvider.notifier).selectTable(table.name);
                          _sqlController.text = ref.read(databaseViewerProvider.notifier).generateSelectQuery(table.name);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(DatabaseViewerState dbState, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          FilledButton.tonalIcon(
            onPressed: _pickDatabase,
            icon: const Icon(LucideIcons.folder_open, size: 14),
            label: Text(dbState.dbPath != null
                ? dbState.dbPath!.split(Platform.pathSeparator).last
                : 'Open .db file'),
          ),
          const SizedBox(width: 8),
          if (dbState.tables.isNotEmpty)
            Text('${dbState.tables.length} tables', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
          const Spacer(),
          if (dbState.lastResult != null && dbState.lastResult!.isSuccess)
            Text(
              '${dbState.lastResult!.rows.length} rows · ${dbState.lastResult!.duration.inMilliseconds}ms',
              style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.database, size: 64, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text('Open a SQLite database', style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 16)),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: _pickDatabase,
            child: const Text('Browse Files'),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(DatabaseViewerState dbState, ColorScheme colorScheme) {
    return Column(
      children: [
        Expanded(
          flex: 3,
          child: dbState.lastResult != null
              ? _buildResultsTable(dbState.lastResult!, colorScheme)
              : Center(
                  child: Text(
                    'Run a query to see results',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                ),
        ),
        Container(
          height: 120,
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.terminal, size: 12, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text('SQL', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                    const Spacer(),
                    FilledButton.tonal(
                      onPressed: _executeQuery,
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Run', style: TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _sqlController,
                  maxLines: null,
                  expands: true,
                  decoration: const InputDecoration(
                    hintText: 'SELECT * FROM table_name',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(8),
                  ),
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  onSubmitted: (_) => _executeQuery(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildResultsTable(QueryResult result, ColorScheme colorScheme) {
    if (result.columns.isEmpty && result.affectedRows > 0) {
      return Center(
        child: Text(
          '${result.affectedRows} row(s) affected',
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
      );
    }

    if (result.columns.isEmpty) {
      return Center(
        child: Text(
          result.error ?? 'No results',
          style: TextStyle(color: result.error != null ? Colors.red : colorScheme.onSurfaceVariant),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        controller: _scrollController,
        child: DataTable(
          headingTextStyle: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
          dataTextStyle: TextStyle(
            fontSize: 11,
            fontFamily: 'monospace',
            color: colorScheme.onSurface,
          ),
          columns: result.columns.map((col) => DataColumn(
            label: Text(col),
          )).toList(),
          rows: result.rows.map((row) => DataRow(
            cells: row.map((cell) => DataCell(
              Text(cell?.toString() ?? 'NULL'),
            )).toList(),
          )).toList(),
        ),
      ),
    );
  }
}
