import 'package:latlong2/latlong.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/route_model.dart';
import '../models/route_point.dart';
import '../models/route_statistics.dart';
import '../models/route_waypoint.dart';

import 'database_service.dart';

class RouteStorageService {
  RouteStorageService._();

  static final RouteStorageService instance =
      RouteStorageService._();

  final DatabaseService _databaseService =
      DatabaseService.instance;

  // =========================================================
  // ЗБЕРЕЖЕННЯ МАРШРУТУ ЛОКАЛЬНО
  // =========================================================

  Future<void> saveRoute(
    RouteModel route, {
    String syncStatus = 'pending',
  }) async {
    final db =
        await _databaseService.database;

    final user =
        Supabase.instance.client.auth.currentUser;

    if (user == null) {
      throw Exception(
        'Користувач не авторизований',
      );
    }

    await db.transaction(
      (transaction) async {
        // ---------------------------------------------------
        // ROUTE
        // ---------------------------------------------------

        await transaction.insert(
          'routes',
          {
            'id': route.id,
            'name': route.name,
            'user_id': user.id,
            'start_time':
                route.startTime.toIso8601String(),
            'end_time':
                route.endTime?.toIso8601String(),
            'sync_status':
                syncStatus,
          },
          conflictAlgorithm:
              ConflictAlgorithm.replace,
        );

        // ---------------------------------------------------
        // ОЧИЩЕННЯ СТАРИХ ДОЧІРНІХ ДАНИХ
        // ---------------------------------------------------

        await transaction.delete(
          'route_points',
          where:
              'route_id = ?',
          whereArgs: [
            route.id,
          ],
        );

        await transaction.delete(
          'waypoints',
          where:
              'route_id = ?',
          whereArgs: [
            route.id,
          ],
        );

        await transaction.delete(
          'route_statistics',
          where:
              'route_id = ?',
          whereArgs: [
            route.id,
          ],
        );

        // ---------------------------------------------------
        // GPS ТОЧКИ
        // ---------------------------------------------------

        for (int i = 0;
            i < route.points.length;
            i++) {
          final point =
              route.points[i];

          await transaction.insert(
            'route_points',
            {
              'route_id':
                  route.id,
              'latitude':
                  point.position.latitude,
              'longitude':
                  point.position.longitude,
              'recorded_at':
                  point.recordedAt
                      .toIso8601String(),
              'accuracy':
                  point.accuracy,
              'point_order':
                  i,
            },
          );
        }

        // ---------------------------------------------------
        // WAYPOINTS
        // ---------------------------------------------------

        for (final waypoint
            in route.waypoints) {
          await transaction.insert(
            'waypoints',
            {
              'route_id':
                  route.id,
              'latitude':
                  waypoint.position.latitude,
              'longitude':
                  waypoint.position.longitude,
              'title':
                  waypoint.title,
              'description':
                  waypoint.description,
              'created_at':
                  waypoint.createdAt
                      .toIso8601String(),
            },
          );
        }

        // ---------------------------------------------------
        // СТАТИСТИКА
        // ---------------------------------------------------

        if (route.statistics != null) {
          final statistics =
              route.statistics!;

          await transaction.insert(
            'route_statistics',
            {
              'route_id':
                  route.id,
              'distance_meters':
                  statistics.distanceMeters,
              'duration_seconds':
                  statistics.durationSeconds,
              'average_speed_kmh':
                  statistics.averageSpeedKmh,
            },
          );
        }
      },
    );
  }

  // =========================================================
  // ЗМІНА НАЗВИ МАРШРУТУ
  // =========================================================

  Future<void> updateRouteName(
    String routeId,
    String? name,
  ) async {
    final db =
        await _databaseService.database;

    final normalizedName =
        name?.trim();

    await db.update(
      'routes',
      {
        'name':
            normalizedName == null ||
                    normalizedName.isEmpty
                ? null
                : normalizedName,

        // Після зміни назви маршрут
        // треба повторно синхронізувати.
        'sync_status':
            'pending',
      },
      where:
          'id = ?',
      whereArgs: [
        routeId,
      ],
    );
  }

  // =========================================================
  // ПОЗНАЧИТИ ЯК SYNCED
  // =========================================================

  Future<void> markAsSynced(
    String routeId,
  ) async {
    final db =
        await _databaseService.database;

    await db.update(
      'routes',
      {
        'sync_status':
            'synced',
      },
      where:
          'id = ?',
      whereArgs: [
        routeId,
      ],
    );
  }

  // =========================================================
  // ПОЗНАЧИТИ ЯК PENDING
  // =========================================================

  Future<void> markAsPending(
    String routeId,
  ) async {
    final db =
        await _databaseService.database;

    await db.update(
      'routes',
      {
        'sync_status':
            'pending',
      },
      where:
          'id = ?',
      whereArgs: [
        routeId,
      ],
    );
  }

  // =========================================================
  // PENDING-МАРШРУТИ
  // =========================================================

  Future<List<RouteModel>>
      getPendingRoutes() async {
    final user =
        Supabase.instance.client.auth.currentUser;

    if (user == null) {
      return [];
    }

    final db =
        await _databaseService.database;

    final routeRows =
        await db.query(
      'routes',
      where:
          'user_id = ? AND sync_status = ?',
      whereArgs: [
        user.id,
        'pending',
      ],
      orderBy:
          'start_time ASC',
    );

    return _buildRoutesFromRows(
      db,
      routeRows,
    );
  }

  // =========================================================
  // ВСІ МАРШРУТИ ПОТОЧНОГО КОРИСТУВАЧА
  // =========================================================

  Future<List<RouteModel>>
      getRoutes() async {
    final user =
        Supabase.instance.client.auth.currentUser;

    if (user == null) {
      return [];
    }

    final db =
        await _databaseService.database;

    final routeRows =
        await db.query(
      'routes',
      where:
          'user_id = ?',
      whereArgs: [
        user.id,
      ],
      orderBy:
          'start_time DESC',
    );

    return _buildRoutesFromRows(
      db,
      routeRows,
    );
  }

  // =========================================================
  // ПОБУДОВА ROUTEMODEL З SQLITE
  // =========================================================

  Future<List<RouteModel>>
      _buildRoutesFromRows(
    Database db,
    List<Map<String, Object?>> routeRows,
  ) async {
    final List<RouteModel> routes = [];

    for (final routeRow
        in routeRows) {
      final routeId =
          routeRow['id'] as String;

      // -----------------------------------------------------
      // GPS POINTS
      // -----------------------------------------------------

      final pointRows =
          await db.query(
        'route_points',
        where:
            'route_id = ?',
        whereArgs: [
          routeId,
        ],
        orderBy:
            'point_order ASC',
      );

      // -----------------------------------------------------
      // WAYPOINTS
      // -----------------------------------------------------

      final waypointRows =
          await db.query(
        'waypoints',
        where:
            'route_id = ?',
        whereArgs: [
          routeId,
        ],
        orderBy:
            'created_at ASC',
      );

      // -----------------------------------------------------
      // STATISTICS
      // -----------------------------------------------------

      final statisticsRows =
          await db.query(
        'route_statistics',
        where:
            'route_id = ?',
        whereArgs: [
          routeId,
        ],
        limit:
            1,
      );

      // -----------------------------------------------------
      // POINT MODELS
      // -----------------------------------------------------

      final points =
          pointRows.map(
        (row) {
          return RoutePoint(
            position:
                LatLng(
              (row['latitude']
                      as num)
                  .toDouble(),
              (row['longitude']
                      as num)
                  .toDouble(),
            ),
            recordedAt:
                DateTime.parse(
              row['recorded_at']
                  as String,
            ),
            accuracy:
                (row['accuracy']
                        as num?)
                    ?.toDouble(),
          );
        },
      ).toList();

      // -----------------------------------------------------
      // WAYPOINT MODELS
      // -----------------------------------------------------

      final waypoints =
          waypointRows.map(
        (row) {
          return RouteWaypoint(
            position:
                LatLng(
              (row['latitude']
                      as num)
                  .toDouble(),
              (row['longitude']
                      as num)
                  .toDouble(),
            ),
            title:
                row['title']
                    as String,
            description:
                row['description']
                        as String? ??
                    '',
            createdAt:
                DateTime.parse(
              row['created_at']
                  as String,
            ),
          );
        },
      ).toList();

      // -----------------------------------------------------
      // STATISTICS MODEL
      // -----------------------------------------------------

      RouteStatistics?
          statistics;

      if (statisticsRows.isNotEmpty) {
        final row =
            statisticsRows.first;

        statistics =
            RouteStatistics(
          distanceMeters:
              (row['distance_meters']
                      as num)
                  .toDouble(),
          durationSeconds:
              (row['duration_seconds']
                      as num)
                  .toInt(),
          averageSpeedKmh:
              (row['average_speed_kmh']
                      as num)
                  .toDouble(),
        );
      }

      // -----------------------------------------------------
      // ROUTE MODEL
      // -----------------------------------------------------

      routes.add(
        RouteModel(
          id:
              routeId,

          name:
              routeRow['name']
                  as String?,

          startTime:
              DateTime.parse(
            routeRow['start_time']
                as String,
          ),

          endTime:
              routeRow['end_time'] ==
                      null
                  ? null
                  : DateTime.parse(
                      routeRow['end_time']
                          as String,
                    ),

          points:
              points,

          waypoints:
              waypoints,

          statistics:
              statistics,
        ),
      );
    }

    return routes;
  }

  // =========================================================
  // СТАТУС СИНХРОНІЗАЦІЇ
  // =========================================================

  Future<String?> getSyncStatus(
    String routeId,
  ) async {
    final db =
        await _databaseService.database;

    final rows =
        await db.query(
      'routes',
      columns: [
        'sync_status',
      ],
      where:
          'id = ?',
      whereArgs: [
        routeId,
      ],
      limit:
          1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return rows.first[
        'sync_status'] as String?;
  }

  // =========================================================
  // ВИДАЛЕННЯ МАРШРУТУ
  // =========================================================

  Future<void> deleteRoute(
    String routeId,
  ) async {
    final db =
        await _databaseService.database;

    await db.delete(
      'routes',
      where:
          'id = ?',
      whereArgs: [
        routeId,
      ],
    );
  }

  // =========================================================
  // ВИДАЛЕННЯ ВСІХ МАРШРУТІВ КОРИСТУВАЧА
  // =========================================================

  Future<void> clearRoutes() async {
    final user =
        Supabase.instance.client.auth.currentUser;

    if (user == null) {
      return;
    }

    final db =
        await _databaseService.database;

    await db.delete(
      'routes',
      where:
          'user_id = ?',
      whereArgs: [
        user.id,
      ],
    );
  }
}