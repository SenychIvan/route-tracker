class RouteStatistics {
  final double distanceMeters;
  final int durationSeconds;
  final double averageSpeedKmh;

  const RouteStatistics({
    required this.distanceMeters,
    required this.durationSeconds,
    required this.averageSpeedKmh,
  });

  double get distanceKm => distanceMeters / 1000;

  String get formattedDuration {
    final duration = Duration(
      seconds: durationSeconds,
    );

    final hours =
        duration.inHours.toString().padLeft(2, '0');

    final minutes =
        (duration.inMinutes % 60)
            .toString()
            .padLeft(2, '0');

    final seconds =
        (duration.inSeconds % 60)
            .toString()
            .padLeft(2, '0');

    return '$hours:$minutes:$seconds';
  }

  factory RouteStatistics.calculate({
    required double distanceMeters,
    required int durationSeconds,
  }) {
    final distanceKm = distanceMeters / 1000;
    final durationHours = durationSeconds / 3600;

    final averageSpeed = durationHours > 0
        ? distanceKm / durationHours
        : 0.0;

    return RouteStatistics(
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
      averageSpeedKmh: averageSpeed,
    );
  }
}