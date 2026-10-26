import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/route_point.dart';

class TrackingService {
  final List<RoutePoint> _routePoints = [];

  double _distanceMeters = 0;

  List<RoutePoint> get routePoints =>
      List.unmodifiable(_routePoints);

  double get distanceMeters => _distanceMeters;

  void start(Position position) {
    reset();

    _routePoints.add(
      _createRoutePoint(position),
    );
  }

  void addPosition(Position position) {
    final newPoint = _createRoutePoint(position);

    if (_routePoints.isNotEmpty) {
      final previousPoint =
          _routePoints.last;

      final distance =
          Geolocator.distanceBetween(
        previousPoint.latitude,
        previousPoint.longitude,
        newPoint.latitude,
        newPoint.longitude,
      );

      _distanceMeters += distance;
    }

    _routePoints.add(newPoint);
  }

  /// Викликається після паузи.
  ///
  /// Поточна позиція стає новою стартовою
  /// точкою, але відстань, пройдена під час
  /// паузи, не додається.
  void resumeAt(Position position) {
    if (_routePoints.isEmpty) {
      _routePoints.add(
        _createRoutePoint(position),
      );

      return;
    }

    final currentPoint =
        LatLng(
      position.latitude,
      position.longitude,
    );

    final lastPoint =
        _routePoints.last.position;

    if (currentPoint.latitude ==
            lastPoint.latitude &&
        currentPoint.longitude ==
            lastPoint.longitude) {
      return;
    }

    _routePoints.add(
      _createRoutePoint(position),
    );
  }

  void reset() {
    _routePoints.clear();
    _distanceMeters = 0;
  }

  RoutePoint _createRoutePoint(
    Position position,
  ) {
    return RoutePoint(
      position: LatLng(
        position.latitude,
        position.longitude,
      ),
      recordedAt: DateTime.now(),
      accuracy: position.accuracy,
    );
  }
}