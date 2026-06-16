enum HazardType {
  speedBreaker,
  pothole,
  railwayCrossing,
  schoolZone,
  village,
  forest,
  sharpCurve;

  // Converts database string back to our concrete Enum
  static HazardType fromString(String value) {
    return HazardType.values.firstWhere(
          (e) => e.name == value,
      orElse: () => HazardType.speedBreaker,
    );
  }
}

class Hazard {
  final int? id;
  final HazardType type;
  final String name;
  final double latitude;
  final double longitude;

  Hazard({
    this.id,
    required this.type,
    required this.name,
    required this.latitude,
    required this.longitude,
  });

  // Convert Hazard object into a Map for SQLite insertion
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type.name, // Saves enum as a readable string
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
    };
  }

  // Create a Hazard object from an SQLite Map database row
  factory Hazard.fromMap(Map<String, dynamic> map) {
    return Hazard(
      id: map['id'] as int?,
      type: HazardType.fromString(map['type'] as String),
      name: map['name'] as String,
      latitude: map['latitude'] as double,
      longitude: map['longitude'] as double,
    );
  }
}