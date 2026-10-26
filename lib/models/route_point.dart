import 'package:latlong2/latlong.dart';

class RoutePoint {
  final LatLng position;
  final DateTime recordedAt;
  final double? accuracy;

  RoutePoint({
    required this.position,
    required this.recordedAt,
    this.accuracy,
  });

  double get latitude => position.latitude;

  double get longitude => position.longitude;
}