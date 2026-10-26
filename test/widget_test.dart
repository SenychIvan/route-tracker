import 'package:flutter_test/flutter_test.dart';
import 'package:route_tracker/main.dart';

void main() {
  test('RouteTrackerApp створюється', () {
    const app = RouteTrackerApp();

    expect(
      app,
      isA<RouteTrackerApp>(),
    );
  });
}