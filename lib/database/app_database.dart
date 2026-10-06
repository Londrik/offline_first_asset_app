import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

part 'app_database.g.dart';

@TableIndex(name: 'idx_assets_sync_status', columns: {#syncStatus})
class Assets extends Table {
  TextColumn get id => text()();
  TextColumn get assetTag => text().unique()();
  TextColumn get name => text()();
  TextColumn get status => text()(); // 'OPERATIONAL' | 'MAINTENANCE' | 'DECOMMISSIONED'
  IntColumn get serverVersion => integer()();
  DateTimeColumn get localUpdatedAt => dateTime()();
  TextColumn get syncStatus => text()(); // 'SYNCED' | 'DIRTY' | 'CONFLICT'

  @override
  Set<Column> get primaryKey => {id};
}

@TableIndex(name: 'idx_mutations_fifo', columns: {#clientTimestamp, #retryCount})
class PendingMutations extends Table {
  TextColumn get id => text()();
  TextColumn get aggregateId => text()();
  TextColumn get aggregateType => text()();
  TextColumn get action => text()(); // 'CREATE' | 'UPDATE' | 'DELETE'
  TextColumn get payload => text()(); // JSON delta
  IntColumn get baseVersion => integer()();
  DateTimeColumn get clientTimestamp => dateTime()();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [Assets, PendingMutations])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? e]) : super(e ?? _openConnection());

  @override
  int get schemaVersion => 1;

  static LazyDatabase _openConnection() {
    return LazyDatabase(() async {
      final dbFolder = await getApplicationDocumentsDirectory();
      final file = File(p.join(dbFolder.path, 'app.sqlite'));
      return NativeDatabase.createInBackground(file);
    });
  }
}
