import 'package:geolocator/geolocator.dart';

class LocationService {
  Future<Position> getCurrentPosition() async {
    final serviceEnabled =
        await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      throw LocationServiceException(
        'Геолокація вимкнена',
      );
    }

    LocationPermission permission =
        await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission =
          await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw LocationServiceException(
        'Доступ до геолокації не надано',
      );
    }

    if (permission ==
        LocationPermission.deniedForever) {
      throw LocationServiceException(
        'Доступ до геолокації заборонено назавжди',
      );
    }

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
    );

    return Geolocator.getCurrentPosition(
      locationSettings: locationSettings,
    );
  }

  Stream<Position> getPositionStream({
    int distanceFilter = 3,
  }) {
    final locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: distanceFilter,
    );

    return Geolocator.getPositionStream(
      locationSettings: locationSettings,
    );
  }
}

class LocationServiceException
    implements Exception {
  final String message;

  LocationServiceException(this.message);

  @override
  String toString() {
    return message;
  }
}