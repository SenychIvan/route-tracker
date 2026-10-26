import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseService {
  DatabaseService._();

  static final DatabaseService instance =
      DatabaseService._();

  Database? _database;

  // =========================================================
  // DATABASE GETTER
  // =========================================================

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    _database = await _initDatabase();

    return _database!;
  }

  // =========================================================
  // ІНІЦІАЛІЗАЦІЯ БАЗИ
  // =========================================================

  Future<Database> _initDatabase() async {
    final databasePath =
        await getDatabasesPath();

    final path = join(
      databasePath,
      'route_tracker.db',
    );

    return openDatabase(
      path,

      // Версія 3:
      // v1 -> базові таблиці
      // v2 -> user_id + sync_status
      // v3 -> name
      version: 3,

      // =====================================================
      // FOREIGN KEYS
      // =====================================================

      onConfigure: (db) async {
        await db.execute(
          'PRAGMA foreign_keys = ON',
        );
      },

      // =====================================================
      // СТВОРЕННЯ НОВОЇ БАЗИ
      // =====================================================

      onCreate: (
        db,
        version,
      ) async {
        // ---------------------------------------------------
        // ROUTES
        // ---------------------------------------------------

        await db.execute('''
          CREATE TABLE routes (
            id TEXT PRIMARY KEY,

            name TEXT,

            user_id TEXT,

            start_time TEXT NOT NULL,

            end_time TEXT,

            sync_status TEXT NOT NULL
              DEFAULT 'pending'
          )
        ''');

        // ---------------------------------------------------
        // ROUTE POINTS
        // ---------------------------------------------------

        await db.execute('''
          CREATE TABLE route_points (
            id INTEGER PRIMARY KEY AUTOINCREMENT,

            route_id TEXT NOT NULL,

            latitude REAL NOT NULL,

            longitude REAL NOT NULL,

            recorded_at TEXT NOT NULL,

            accuracy REAL,

            point_order INTEGER NOT NULL,

            FOREIGN KEY (route_id)
              REFERENCES routes(id)
              ON DELETE CASCADE
          )
        ''');

        // ---------------------------------------------------
        // WAYPOINTS
        // ---------------------------------------------------

        await db.execute('''
          CREATE TABLE waypoints (
            id INTEGER PRIMARY KEY AUTOINCREMENT,

            route_id TEXT NOT NULL,

            latitude REAL NOT NULL,

            longitude REAL NOT NULL,

            title TEXT NOT NULL,

            description TEXT,

            created_at TEXT NOT NULL,

            FOREIGN KEY (route_id)
              REFERENCES routes(id)
              ON DELETE CASCADE
          )
        ''');

        // ---------------------------------------------------
        // ROUTE STATISTICS
        // ---------------------------------------------------

        await db.execute('''
          CREATE TABLE route_statistics (
            route_id TEXT PRIMARY KEY,

            distance_meters REAL NOT NULL,

            duration_seconds INTEGER NOT NULL,

            average_speed_kmh REAL NOT NULL,

            FOREIGN KEY (route_id)
              REFERENCES routes(id)
              ON DELETE CASCADE
          )
        ''');

        // ---------------------------------------------------
        // INDEXES
        // ---------------------------------------------------

        await _createIndexes(
          db,
        );
      },

      // =====================================================
      // ОНОВЛЕННЯ СТАРОЇ БАЗИ
      // =====================================================

      onUpgrade: (
        db,
        oldVersion,
        newVersion,
      ) async {
        // ---------------------------------------------------
        // VERSION 1 -> VERSION 2
        //
        // Додаємо користувача
        // та статус синхронізації.
        // ---------------------------------------------------

        if (oldVersion < 2) {
          await db.execute('''
            ALTER TABLE routes
            ADD COLUMN user_id TEXT
          ''');

          await db.execute('''
            ALTER TABLE routes
            ADD COLUMN sync_status TEXT
            NOT NULL
            DEFAULT 'pending'
          ''');

          await _createIndexes(
            db,
          );
        }

        // ---------------------------------------------------
        // VERSION 2 -> VERSION 3
        //
        // Додаємо назву маршруту.
        // ---------------------------------------------------

        if (oldVersion < 3) {
          await db.execute('''
            ALTER TABLE routes
            ADD COLUMN name TEXT
          ''');
        }
      },
    );
  }

  // =========================================================
  // INDEXES
  // =========================================================

  static Future<void> _createIndexes(
    Database db,
  ) async {
    // -------------------------------------------------------
    // ROUTES -> USER
    // -------------------------------------------------------

    await db.execute('''
      CREATE INDEX IF NOT EXISTS
      idx_routes_user_id
      ON routes(user_id)
    ''');

    // -------------------------------------------------------
    // ROUTES -> SYNC STATUS
    // -------------------------------------------------------

    await db.execute('''
      CREATE INDEX IF NOT EXISTS
      idx_routes_sync_status
      ON routes(sync_status)
    ''');

    // -------------------------------------------------------
    // ROUTE POINTS
    // -------------------------------------------------------

    await db.execute('''
      CREATE INDEX IF NOT EXISTS
      idx_route_points_route_id
      ON route_points(route_id)
    ''');

    // -------------------------------------------------------
    // WAYPOINTS
    // -------------------------------------------------------

    await db.execute('''
      CREATE INDEX IF NOT EXISTS
      idx_waypoints_route_id
      ON waypoints(route_id)
    ''');
  }

  // =========================================================
  // CLOSE DATABASE
  // =========================================================

  Future<void> close() async {
    final db =
        _database;

    if (db == null) {
      return;
    }

    await db.close();

    _database = null;
  }
}