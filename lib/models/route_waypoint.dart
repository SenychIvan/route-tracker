import 'package:latlong2/latlong.dart';

class RouteWaypoint {
  final LatLng position;
  final String title;
  final String description;
  final DateTime createdAt;

  RouteWaypoint({
    required this.position,
    required this.title,
    required this.description,
    required this.createdAt,
  });

  double get latitude => position.latitude;

  double get longitude => position.longitude;
}