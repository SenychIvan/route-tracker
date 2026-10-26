import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/route_model.dart';
import '../models/route_point.dart';
import '../models/route_statistics.dart';
import '../models/route_waypoint.dart';

class SupabaseRouteService {
  SupabaseRouteService._();

  static final SupabaseRouteService instance =
      SupabaseRouteService._();

  SupabaseClient get _supabase =>
      Supabase.instance.client;

  // =========================================================
  // ЗБЕРЕЖЕННЯ / СИНХРОНІЗАЦІЯ МАРШРУТУ
  // =========================================================

  Future<void> saveRoute(
    RouteModel route,
  ) async {
    final user =
        _supabase.auth.currentUser;

    if (user == null) {
      throw Exception(
        'Користувач не авторизований',
      );
    }

    // =======================================================
    // ROUTE
    // =======================================================

    await _supabase
        .from('routes')
        .upsert(
      {
        'id':
            route.id,

        // НАЗВА МАРШРУТУ
        'name':
            route.name,

        'user_id':
            user.id,

        'start_time':
            route.startTime
                .toUtc()
                .toIso8601String(),

        'end_time':
            route.endTime
                ?.toUtc()
                .toIso8601String(),
      },
      onConflict: 'id',
    );

    // =======================================================
    // ПЕРЕД ПОВТОРНОЮ СИНХРОНІЗАЦІЄЮ
    // ВИДАЛЯЄМО СТАРІ ДОЧІРНІ ЗАПИСИ
    // =======================================================

    await _supabase
        .from('route_points')
        .delete()
        .eq(
          'route_id',
          route.id,
        );

    await _supabase
        .from('waypoints')
        .delete()
        .eq(
          'route_id',
          route.id,
        );

    await _supabase
        .from('route_statistics')
        .delete()
        .eq(
          'route_id',
          route.id,
        );

    // =======================================================
    // GPS ТОЧКИ
    // =======================================================

    if (route.points.isNotEmpty) {
      final pointRows =
          <Map<String, dynamic>>[];

      for (int i = 0;
          i < route.points.length;
          i++) {
        final point =
            route.points[i];

        pointRows.add({
          'route_id':
              route.id,

          'latitude':
              point.position.latitude,

          'longitude':
              point.position.longitude,

          'recorded_at':
              point.recordedAt
                  .toUtc()
                  .toIso8601String(),

          'accuracy':
              point.accuracy,

          'point_order':
              i,
        });
      }

      await _supabase
          .from('route_points')
          .insert(
            pointRows,
          );
    }

    // =======================================================
    // WAYPOINTS
    // =======================================================

    if (route.waypoints.isNotEmpty) {
      final waypointRows =
          route.waypoints
              .map(
        (
          waypoint,
        ) {
          return {
            'route_id':
                route.id,

            'latitude':
                waypoint
                    .position
                    .latitude,

            'longitude':
                waypoint
                    .position
                    .longitude,

            'title':
                waypoint.title,

            'description':
                waypoint.description,

            'created_at':
                waypoint.createdAt
                    .toUtc()
                    .toIso8601String(),
          };
        },
      ).toList();

      await _supabase
          .from('waypoints')
          .insert(
            waypointRows,
          );
    }

    // =======================================================
    // СТАТИСТИКА
    // =======================================================

    if (route.statistics != null) {
      final statistics =
          route.statistics!;

      await _supabase
          .from('route_statistics')
          .insert({
        'route_id':
            route.id,

        'distance_meters':
            statistics.distanceMeters,

        'duration_seconds':
            statistics.durationSeconds,

        'average_speed_kmh':
            statistics.averageSpeedKmh,
      });
    }
  }

  // =========================================================
  // ОТРИМАННЯ МАРШРУТІВ ПОТОЧНОГО КОРИСТУВАЧА
  // =========================================================

  Future<List<RouteModel>>
      getRoutes() async {
    final user =
        _supabase.auth.currentUser;

    if (user == null) {
      throw Exception(
        'Користувач не авторизований',
      );
    }

    // =======================================================
    // ROUTES
    // =======================================================

    final routeRows =
        await _supabase
            .from('routes')
            .select()
            .eq(
              'user_id',
              user.id,
            )
            .order(
              'start_time',
              ascending: false,
            );

    final List<RouteModel>
        routes = [];

    for (final routeRow
        in routeRows) {
      final routeId =
          routeRow['id']
              as String;

      // =====================================================
      // GPS POINTS
      // =====================================================

      final pointRows =
          await _supabase
              .from('route_points')
              .select()
              .eq(
                'route_id',
                routeId,
              )
              .order(
                'point_order',
                ascending: true,
              );

      final points =
          pointRows
              .map<RoutePoint>(
        (
          row,
        ) {
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
            ).toLocal(),

            accuracy:
                (row['accuracy']
                        as num?)
                    ?.toDouble(),
          );
        },
      ).toList();

      // =====================================================
      // WAYPOINTS
      // =====================================================

      final waypointRows =
          await _supabase
              .from('waypoints')
              .select()
              .eq(
                'route_id',
                routeId,
              )
              .order(
                'created_at',
                ascending: true,
              );

      final waypoints =
          waypointRows
              .map<RouteWaypoint>(
        (
          row,
        ) {
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
            ).toLocal(),
          );
        },
      ).toList();

      // =====================================================
      // STATISTICS
      // =====================================================

      final statisticsRows =
          await _supabase
              .from(
                'route_statistics',
              )
              .select()
              .eq(
                'route_id',
                routeId,
              );

      RouteStatistics?
          statistics;

      if (statisticsRows
          .isNotEmpty) {
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

      // =====================================================
      // ROUTE MODEL
      // =====================================================

      routes.add(
        RouteModel(
          id:
              routeId,

          // НАЗВА З SUPABASE
          name:
              routeRow['name']
                  as String?,

          startTime:
              DateTime.parse(
            routeRow['start_time']
                as String,
          ).toLocal(),

          endTime:
              routeRow['end_time'] ==
                      null
                  ? null
                  : DateTime.parse(
                      routeRow[
                              'end_time']
                          as String,
                    ).toLocal(),

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
  // ВИДАЛЕННЯ МАРШРУТУ
  // =========================================================

  Future<void> deleteRoute(
    String routeId,
  ) async {
    final user =
        _supabase.auth.currentUser;

    if (user == null) {
      throw Exception(
        'Користувач не авторизований',
      );
    }

    await _supabase
        .from('routes')
        .delete()
        .eq(
          'id',
          routeId,
        )
        .eq(
          'user_id',
          user.id,
        );

    // route_points,
    // waypoints,
    // route_statistics
    // видаляться через ON DELETE CASCADE.
  }
}