import 'package:sqflite_common_ffi/sqflite_ffi.dart' as sqflite_ffi;

void initDesktopSqlite() {
  sqflite_ffi.sqfliteFfiInit();
  sqflite_ffi.databaseFactory = sqflite_ffi.databaseFactoryFfi;
}
