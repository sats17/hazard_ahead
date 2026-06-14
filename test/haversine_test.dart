import 'package:flutter_test/flutter_test.dart';
import 'package:speed_breaker_alert/core/utils/haversine.dart';

void main() {
  test('haversine distance known points', () {
    // Mumbai (approx) to Pune (approx)
    final mumbaiLat = 19.0760;
    final mumbaiLon = 72.8777;
    final puneLat = 18.5204;
    final puneLon = 73.8567;

    final d = haversineDistanceMeters(mumbaiLat, mumbaiLon, puneLat, puneLon);
    // Expected distance for these points is ~120 km; allow a reasonable tolerance
    expect(d, greaterThan(110000));
    expect(d, lessThan(130000));
  });
}

