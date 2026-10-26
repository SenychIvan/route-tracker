import 'route_point.dart';
import 'route_statistics.dart';
import 'route_waypoint.dart';

class RouteModel {
  final String id;

  final String? name;

  final DateTime startTime;
  final DateTime? endTime;

  final List<RoutePoint> points;
  final List<RouteWaypoint> waypoints;

  final RouteStatistics? statistics;

  RouteModel({
    required this.id,
    this.name,
    required this.startTime,
    this.endTime,
    required this.points,
    required this.waypoints,
    this.statistics,
  });

  bool get isFinished =>
      endTime != null;

  String get displayName {
    final value =
        name?.trim();

    if (value == null ||
        value.isEmpty) {
      return 'Маршрут';
    }

    return value;
  }
}