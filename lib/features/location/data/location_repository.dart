// ...existing code...

/// Stub repository for location updates.
/// Real implementation should live in features/location/data and use `geolocator`.
abstract class LocationRepository {
  /// Stream of position updates (latitude, longitude)
  Stream<Map<String, double>> positionStream();

  /// One-off request for current position
  Future<Map<String, double>> getCurrentPosition();
}

