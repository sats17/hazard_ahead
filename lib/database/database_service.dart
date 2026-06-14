import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

import '../core/constants/hazard_type.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final databaseServiceProvider = Provider<DatabaseService>((ref) {
  return DatabaseService(); // Notice we don't need the static .instance anymore
});

// 2. Create a FutureProvider to handle the async initialization of the actual DB
final databaseProvider = FutureProvider<Database>((ref) async {
  final dbService = ref.watch(databaseServiceProvider);
  return await dbService.database;
});

class DatabaseService {
  // Singleton pattern so we only have one database connection
  Database? _database;

  DatabaseService();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('speedbreaker.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    // Get the device's exact location for saving permanent documents
    final dbPath = await getApplicationDocumentsDirectory();
    final path = join(dbPath.path, filePath);

    // Open or create the database
    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  // Create the Table Schema defined in your specs
  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE hazards (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        name TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL
      )
    ''');
  }

  // A quick method to check how many hazards we have saved
  Future<int> getHazardCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) FROM hazards');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> insertHazardsBulk(List<Hazard> hazards) async {
    final db = await database; // Your SQLite db instance
    final batch = db.batch();

    for (var hazard in hazards) {
      batch.insert(
        'hazards',
        hazard.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  Future<List<Hazard>> getNearbyHazards(double userLat, double userLon) async {
    final db = await database;

    // ~500 meters roughly translates to 0.0045 degrees
    double delta = 0.0045;

    final List<Map<String, dynamic>> maps = await db.query(
      'hazards',
      where: 'latitude BETWEEN ? AND ? AND longitude BETWEEN ? AND ?',
      whereArgs: [
        userLat - delta,
        userLat + delta,
        userLon - delta,
        userLon + delta
      ],
    );

    return List.generate(maps.length, (i) {
      return Hazard(
        id: maps[i]['id'],
        type: HazardType.values.firstWhere((e) => e.name == maps[i]['type']),
        latitude: maps[i]['latitude'],
        longitude: maps[i]['longitude'],
        name: maps[i]['name'],
      );
    });
  }

  Future<void> debugPrintDatabaseContents() async {
    final db = await database; // Use your existing database getter

    // Query all rows from the hazards table
    final List<Map<String, dynamic>> maps = await db.query('hazards');

    print('--- DATABASE CONTENTS (${maps.length} rows) ---');
    for (var row in maps) {
      print('ID: ${row['id']}, Type: ${row['type']}, Lat: ${row['latitude']}, Lon: ${row['longitude']}, Name: ${row['name']}');
    }
    print('-------------------------------------------');
  }
}